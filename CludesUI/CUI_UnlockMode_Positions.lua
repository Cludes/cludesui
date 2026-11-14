if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnlockMode_Positions.lua
--  Ghost overlays, override anchors, saved positions, grow-direction
--  positioning, bar frame resolution, apply saved positions on login,
--  Edit Mode anchor guard.
--  Loaded after CUI_UnlockMode.lua; _unlockCoreInit runs it once with UM.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)
CUI_NS.unlockParts = CUI_NS.unlockParts or {}
CUI_NS.unlockParts.Positions = function(LM)
    local mod, ABAR, Pix, FONT_PATH = CUI_NS, LM.EAB, LM.PP, LM.FONT_PATH
    local BAR_LOOKUP, registeredElements, registeredOrder, RebuildRegisteredOrder =
        LM.BAR_LOOKUP, LM.registeredElements, LM.registeredOrder, LM.RebuildRegisteredOrder
    local movers, pendingPositions, GetBarGrowDirActual, GetAnchorDB =
        LM.movers, LM.pendingPositions, LM.GetBarGrowDirActual, LM.GetAnchorDB
    local GetAnchorInfo, MatchH, ScheduleAnchorBatch, ApplyAllWidthHeightMatches =
        LM.GetAnchorInfo, LM.MatchH, LM.ScheduleAnchorBatch, LM.ApplyAllWidthHeightMatches
    local HookFrameSizeChanged, FadeOverlayForSelectElement, CancelPickMode =
        LM.HookFrameSizeChanged, LM.FadeOverlayForSelectElement, LM.CancelPickMode

    -- isPositionHeld: something else places the frame for now (the quest tracker
    -- inside Blizzard's managed container), so only a live unlock session moves it.
    local function PositionHeld(key)
        if LM.isUnlocked then
            return false
        end
        local elem = registeredElements[key]
        return elem and elem.isPositionHeld and elem.isPositionHeld(key) or false
    end

    -------------------------------------------------------------------------------
    --  Ghost overlay set (unlock mode only), shared by fallback and override  -- cui-style: allow comment-budget
    --  anchors: draggable 1:1 mover-overlay copies at 75% opacity sitting where
    --  the element lands while the link is engaged; dragging writes the link's
    --  X/Y offsets (relative to the side-snap point). opts: getLink(g) -> stored
    --  {target, side, offsetX, offsetY} or nil; init(g, ...) -> tint r,g,b and the
    --  dark-background mix r,g,b; label(g, fs); onSync(g) (optional, runs before
    --  placement); deselectOther = CludesUI key clearing the other set.
    -------------------------------------------------------------------------------
    local function MakeGhostSet(options)
        local ghosts = {}
        local GHOST_ALPHA = 0.75
        local selectedGhost
        local getLink = options.getLink

        local function SetGhostSelected(g, enabled)
            if not g or not g._brd then
                return
            end
            if enabled then
                g._brd:SetColor(1, 1, 1, 0.9)
            else
                g._brd:SetColor(g._wr or 1, g._wg or 1, g._wb or 1, 0.6)
            end
        end

        local function HideGhost(g)
            if selectedGhost == g then
                SetGhostSelected(g, false)
                selectedGhost = nil
            end
            g._dragging = nil
            g:Hide()
        end

        -- Side-snap center for the child against the link target (frame bounds,
        -- UIParent space) -- the offsets' zero point. Mirrors _TryFallbackAnchor /
        -- _TryOverrideAnchor runtime math (extent is inert in unlock).
        local function GhostSnapBase(childKey, itemLink)
            local childBar = LM.GetBarFrame(childKey)
            local tgt = LM.GetBarFrame(itemLink.target)
            if not childBar or not tgt or not tgt:GetLeft() then
                return nil
            end
            local uiS = UIParent:GetEffectiveScale()
            local tS = tgt:GetEffectiveScale()
            local cS = childBar:GetEffectiveScale()
            local tL = (tgt:GetLeft() or 0) * tS / uiS
            local tR = (tgt:GetRight() or 0) * tS / uiS
            local tT = (tgt:GetTop() or 0) * tS / uiS
            local tB = (tgt:GetBottom() or 0) * tS / uiS
            local tCX = (tL + tR) / 2
            local tCY = (tT + tB) / 2
            local cW = (childBar:GetWidth() or 50) * cS / uiS
            local cH = (childBar:GetHeight() or 50) * cS / uiS
            local side = itemLink.side
            if side == "LEFT" then
                return tL - cW / 2, tCY
            elseif side == "RIGHT" then
                return tR + cW / 2, tCY
            elseif side == "TOP" then
                return tCX, tT + cH / 2
            elseif side == "BOTTOM" then
                return tCX, tB - cH / 2
            end
            return tCX, tCY
        end

        local function SyncGhost(g)
            -- Temporarily hidden for this unlock session (Shift+Right Click, mover
            -- gesture parity). Every refresh path funnels here, so the ghost stays
            -- hidden until the next unlock entry clears the flag.
            if g._tempHidden then
                g:Hide()
                return
            end
            if LM.FilterHides and LM.FilterHides(g._childKey) then
                HideGhost(g)
                return
            end -- element filter
            if g._dragging then
                return
            end
            local childKey = g._childKey
            local itemLink = getLink(g)
            if not itemLink then
                HideGhost(g)
                return
            end
            local cx, cy = GhostSnapBase(childKey, itemLink)
            if not cx then
                HideGhost(g)
                return
            end
            cx = cx + (itemLink.offsetX or 0)
            cy = cy + (itemLink.offsetY or 0)
            -- Size = the ELEMENT's live screen size, never the mover overlay's: hover
            -- expansion inflates the mover, and stored settings go stale if the
            -- element was resized this session. The live frame is always current.
            local eb = LM.GetBarFrame(childKey)
            local wid, hgt
            if eb then
                local es = eb:GetEffectiveScale() / UIParent:GetEffectiveScale()
                wid = (eb:GetWidth() or 50) * es
                hgt = (eb:GetHeight() or 50) * es
                if wid > 0 and hgt > 0 then
                    g:SetSize(wid, hgt)
                end
            end
            -- Mirror the runtime growth-fixed-edge pin (UIParent-space dims = w,h)
            -- so the ghost previews exactly where the bar will land.
            local gsx, gsy = CludesUI._FallbackGrowShift(childKey, itemLink.side, wid or 0, hgt or 0)
            cx = cx + gsx
            cy = cy + gsy
            -- Run the exact runtime pipeline (child-local conversion + dim-aware
            -- pixel snap) so the ghost previews the landed position to the pixel.
            if eb then
                local uiS = UIParent:GetEffectiveScale()
                local cS = eb:GetEffectiveScale()
                local acRatio = uiS / cS
                local bx = (cx - UIParent:GetWidth() / 2) * acRatio
                local by = (cy - UIParent:GetHeight() / 2) * acRatio
                local PPg = Pix or (CludesUI and CludesUI.PP)
                if PPg and PPg.SnapCenterForDim then
                    bx = PPg.SnapCenterForDim(bx, eb:GetWidth() or 0, cS)
                    by = PPg.SnapCenterForDim(by, eb:GetHeight() or 0, cS)
                end
                cx = bx / acRatio + UIParent:GetWidth() / 2
                cy = by / acRatio + UIParent:GetHeight() / 2
            end
            if options.onSync then
                options.onSync(g)
            end
            g:ClearAllPoints()
            g:SetPoint(
                "CENTER",
                UIParent,
                "CENTER",
                cx - UIParent:GetWidth() / 2,
                cy - UIParent:GetHeight() / 2
            )
            g:Show()
        end

        local function CreateGhost(...)
            local g = CreateFrame("Frame", nil, LM.unlockFrame)
            local wr, wg, wb, mr, mg, mb = options.init(g, ...)
            LM.SetMoverOverlayLevel(g, 50)
            g:SetClampedToScreen(true)
            g:EnableMouse(true)
            g:SetAlpha(GHOST_ALPHA)

            g._wr, g._wg, g._wb = wr, wg, wb
            local backdrop = g:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            if LM.darkOverlaysEnabled then
                backdrop:SetColorTexture(
                    0.075 + (mr - 0.075) * 0.10,
                    0.113 + (mg - 0.113) * 0.10,
                    0.141 + (mb - 0.141) * 0.10,
                    0.95
                )
            else
                backdrop:SetColorTexture(wr, wg, wb, 0.10)
            end
            g._brd = CludesUI.MakeBorder(g, wr, wg, wb, 0.6)

            local labelFrame = CreateFrame("Frame", nil, g)
            labelFrame:SetAllPoints()
            labelFrame:SetClipsChildren(true)
            labelFrame:SetFrameLevel(g:GetFrameLevel() + 2)
            local fontStr = labelFrame:CreateFontString(nil, "OVERLAY")
            CludesUI.PrimeFontShadow(fontStr, true)
            fontStr:SetFont(FONT_PATH, 10 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
            fontStr:SetTextColor(1, 1, 1, 0.75)
            fontStr:SetWordWrap(false)
            fontStr:SetNonSpaceWrap(false)
            fontStr:SetPoint("CENTER", g, "CENTER")
            options.label(g, fontStr)

            g:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" then
                    return
                end
                -- One arrow-key target at a time across movers and BOTH ghost systems.
                if CludesUI._DeselectSelectedMover then
                    CludesUI._DeselectSelectedMover()
                end
                local other = CludesUI[options.deselectOther]
                if other then
                    other()
                end
                if selectedGhost and selectedGhost ~= self then
                    SetGhostSelected(selectedGhost, false)
                end
                selectedGhost = self
                SetGhostSelected(self, true)
                -- Immediate manual drag from the first held pixel: the native drag
                -- event only fires past a movement threshold, a huge dead zone for
                -- the subtle adjustments these offsets usually need.
                local gl, gr, gt, gb = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
                if gl then
                    local uiS = UIParent:GetEffectiveScale()
                    local mx, my = GetCursorPosition()
                    local gs = self:GetEffectiveScale() / uiS
                    self._dragging = true
                    self._dragCurX = mx / uiS
                    self._dragCurY = my / uiS
                    self._dragStartCX = (gl + gr) * 0.5 * gs
                    self._dragStartCY = (gt + gb) * 0.5 * gs
                end
            end)
            g:SetScript("OnMouseUp", function(self, button)
                -- Shift+Right Click temporarily hides this ghost for the current
                -- unlock session (regular-mover gesture parity). Cleared on the
                -- next unlock entry; purely visual, the stored link is untouched.
                if button == "RightButton" and IsShiftKeyDown() then
                    self._tempHidden = true
                    self._dragging = nil
                    HideGhost(self)
                    return
                end
                if button ~= "LeftButton" or not self._dragging then
                    return
                end
                self._dragging = nil
                local itemLink = getLink(self)
                if not itemLink then
                    HideGhost(self)
                    return
                end
                local cx, cy = GhostSnapBase(self._childKey, itemLink)
                local gl, gr, gt, gb = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
                if cx and gl then
                    -- Raw center delta: SyncGhost and the runtime apply both pixel-snap
                    -- the FINAL center (dim-aware); snapping the offset would
                    -- double-snap. Store against the growth-fixed edge (subtract the
                    -- shift apply/preview add); inert for center-growth children.
                    local gs = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    local dw = (gr - gl) * gs
                    local dh = (gt - gb) * gs
                    local gsx, gsy = CludesUI._FallbackGrowShift(self._childKey, itemLink.side, dw, dh)
                    itemLink.offsetX = (gl + gr) * 0.5 * gs - cx - gsx
                    itemLink.offsetY = (gt + gb) * 0.5 * gs - cy - gsy
                    LM.hasChanges = true
                end
                SyncGhost(self)
            end)
            -- Per frame: while held follow the cursor exactly (manual drag); otherwise
            -- re-sync on a throttle so the ghost tracks a moved target or a resized
            -- element. Hidden ghosts cost nothing.
            g:SetScript("OnUpdate", function(self, elapsed)
                if self._dragging then
                    local uiS = UIParent:GetEffectiveScale()
                    local mx, my = GetCursorPosition()
                    mx, my = mx / uiS, my / uiS
                    local ncx = self._dragStartCX + (mx - self._dragCurX)
                    local ncy = self._dragStartCY + (my - self._dragCurY)
                    self:ClearAllPoints()
                    self:SetPoint(
                        "CENTER",
                        UIParent,
                        "CENTER",
                        ncx - UIParent:GetWidth() / 2,
                        ncy - UIParent:GetHeight() / 2
                    )
                    return
                end
                self._acc = (self._acc or 0) + elapsed
                if self._acc < 0.25 then
                    return
                end
                self._acc = 0
                SyncGhost(self)
            end)
            return g
        end

        local set = { ghosts = ghosts, Hide = HideGhost, Sync = SyncGhost, Create = CreateGhost }

        function set.HideAll()
            for _, g in pairs(ghosts) do
                HideGhost(g)
            end
        end

        -- Fade support for the unlock open animation: scales the resting ghost
        -- alpha by 0..1 so ghosts ride the same fade-in curve as the movers.
        function set.SetAlpha(mult)
            for _, g in pairs(ghosts) do
                if g:IsShown() then
                    g:SetAlpha(GHOST_ALPHA * (mult or 1))
                end
            end
        end

        function set.Deselect()
            if selectedGhost then
                SetGhostSelected(selectedGhost, false)
                selectedGhost = nil
            end
        end

        -- Clear per-session temp-hides (Shift+Right Click): unlock entry calls this
        -- alongside the mover/Blizz-overlay clears so every session starts with all
        -- ghosts visible again.
        function set.ClearTempHides()
            for _, g in pairs(ghosts) do
                g._tempHidden = nil
            end
        end

        -- Arrow-key nudge for the selected ghost. Same convention as nudging an
        -- anchored element: the exact delta is added to the stored offsets (never a
        -- live geometry read-back) and the shared preview/runtime pipeline pixel-snaps
        -- the landed center. Returns true when consumed.
        function set.Nudge(dx, dy)
            local g = selectedGhost
            if not g or not g:IsShown() then
                return false
            end
            local itemLink = getLink(g)
            if not itemLink then
                return false
            end
            itemLink.offsetX = (itemLink.offsetX or 0) + dx
            itemLink.offsetY = (itemLink.offsetY or 0) + dy
            LM.hasChanges = true
            SyncGhost(g)
            return true
        end

        return set
    end

    -------------------------------------------------------------------------------
    --  Fallback ghosts: each element with a fallback link gets a ghost with a
    --  whitened accent tint, labeled "Fallback: <element>". Exists only while
    --  unlock mode is open, only for elements that opted into a fallback.
    -------------------------------------------------------------------------------
    do
        local set = MakeGhostSet({
            getLink = function(g)
                local saved = GetAnchorDB()
                local details = saved and saved[g._childKey]
                local fb = details and details.fallback
                if fb and fb.target then
                    return fb
                end
                return nil
            end,
            init = function(g, childKey)
                g._childKey = childKey
                -- 10%-whitened mover look: dark background (when dark overlays
                -- are on) and accent border, both lerped a tenth of the way to white.
                local ar, ag, ab = 1, 1, 1
                if CludesUI.GetAccentColor then
                    ar, ag, ab = CludesUI.GetAccentColor()
                end
                return ar + (1 - ar) * 0.10, ag + (1 - ag) * 0.10, ab + (1 - ab) * 0.10, 1, 1, 1
            end,
            label = function(g, fontStr)
                fontStr:SetText(
                    CludesUI.L("Fallback") .. ": " .. (LM.GetBarLabel(g._childKey) or g._childKey)
                )
            end,
            deselectOther = "_DeselectOverrideGhosts",
        })
        local ghosts = set.ghosts

        CludesUI._HideFallbackGhosts = set.HideAll
        CludesUI._SetFallbackGhostsAlpha = set.SetAlpha
        CludesUI._DeselectFallbackGhosts = set.Deselect
        CludesUI._ClearFallbackGhostTempHides = set.ClearTempHides
        CludesUI._NudgeSelectedFallbackGhost = set.Nudge

        function CludesUI._RefreshFallbackGhosts()
            if not LM.isUnlocked or not LM.unlockFrame then
                CludesUI._HideFallbackGhosts()
                return
            end
            local saved = GetAnchorDB()
            for key, g in pairs(ghosts) do
                local details = saved and saved[key]
                if not (details and details.fallback and details.fallback.target) then
                    set.Hide(g)
                end
            end
            if not saved then
                return
            end
            for childKey, details in pairs(saved) do
                local fb = details.fallback
                if fb and fb.target then
                    local g = ghosts[childKey]
                    if not g then
                        g = set.Create(childKey)
                        ghosts[childKey] = g
                    end
                    set.Sync(g)
                end
            end
        end
    end

    -------------------------------------------------------------------------------
    --  Override anchors (opt-in, Resource Bars only): a spec-override group can  -- cui-style: allow comment-budget
    --  hold an alternate ANCHOR LINK {target, side, offsets} for an element --
    --  picked through the same element-pick flow as fallback anchors -- engaged
    --  whenever a member spec is active, no unlock-layer fork is applied and
    --  unlock mode is closed. Same containment contract as fallback anchors: the
    --  engaged position is a transient SetPoint (never written to any saved-
    --  position store, so layout harvests -- which read loadPosition/DB -- never
    --  see it), unlock mode disengages it (movers always edit the baseline; the
    --  ghost edits the override), and the store is ONE profile key
    --  (unlockOverrideAnchors) the override system itself never reads. Free until
    --  stored: one nil check per position apply.
    -------------------------------------------------------------------------------
    do
        local ELIGIBLE = {
            ERB_Health = true,
            ERB_Power = true,
            ERB_ClassResource = true,
            ERB_CastBar = true,
            ERB_GCDBar = true,
            ERB_TotemBar = true,
        }

        -- childKey -> gid whose stored position currently holds the frame. The
        -- reapply sweep repaints released keys through their normal owners.
        local engagedKeys = {}

        -- Pending group id while the element pick mode runs for an override anchor.
        local ovPickGid

        -- store shape: { [childKey] = { [gid] = { target, side, offsetX, offsetY } } }
        -- offsets are UIParent-space deltas from the side-snap point (ghost drags).
        local function Store(create)
            local prof = CludesUI.GetActiveProfileData()
            if not prof then
                return nil
            end
            if create and not prof.unlockOverrideAnchors then
                prof.unlockOverrideAnchors = {}
            end
            return prof.unlockOverrideAnchors
        end

        local function Groups()
            local prof = CludesUI.GetActiveProfileData()
            return prof and prof.specOverrideGroups
        end

        local function GroupName(groupId)
            for _, g in ipairs(Groups() or {}) do
                if g.id == groupId then
                    return g.name
                end
            end
            return nil
        end

        function CludesUI._OverrideAnchorEligible(childKey)
            return ELIGIBLE[childKey] or false
        end

        -- Spec-override groups an Override Anchor may target: groups WITHOUT a
        -- custom unlock layout (a fork owns every position outright, so an
        -- override anchor there would be a dead setting).
        function CludesUI._OverrideAnchorGroups()
            local groups = Groups()
            if not groups or #groups == 0 then
                return nil
            end
            local prof = CludesUI.GetActiveProfileData()
            local layouts = prof and prof.specUnlockOverrides and prof.specUnlockOverrides.layouts
            local result
            for _, g in ipairs(groups) do
                if not (layouts and layouts[g.id]) then
                    result = result or {}
                    result[#result + 1] = g
                end
            end
            return result
        end

        function CludesUI._HasOverrideAnchor(childKey, groupId)
            local storage = Store()
            local ent = storage and storage[childKey]
            local shade = ent and ent[groupId]
            -- Plain boolean chain: an (x and y) ~= nil comparison here would read
            -- boolean FALSE as "has one" and light every group's edit rows up.
            return type(shade) == "table" and shade.target ~= nil
        end

        -- First group in creation order containing the current spec AND holding a
        -- stored position for this element (the OwnerGid convention). nil while
        -- any spec/conditional unlock layer is applied -- forks own every position.
        local function ActiveGidFor(childKey)
            local storage = Store()
            local ent = storage and storage[childKey]
            if not ent then
                return nil
            end
            if CludesUI.SpecOverrides_UnlockActive and CludesUI.SpecOverrides_UnlockActive() ~= nil then
                return nil
            end
            local specID = CludesUI._specID
            if not specID or specID == 0 then
                CludesUI._RefreshSpecID()
                specID = CludesUI._specID
            end
            if not specID or specID == 0 then
                return nil
            end
            -- WoW Forever: the spec the class acts as for Spec Overrides.
            if CludesUI.IS_FOREVER and CludesUI.SpecOverrides_CurrentSpecID then
                specID = CludesUI.SpecOverrides_CurrentSpecID() or specID
            end
            local groups = Groups()
            if not groups then
                return nil
            end
            for _, g in ipairs(groups) do
                if ent[g.id] then
                    for _, spellRef in ipairs(g.specs or {}) do
                        if spellRef == specID then
                            return g.id
                        end
                    end
                end
            end
            return nil
        end

        -- True when this owned positioning for the apply (applied, already in
        -- place, or held); false = normal path. An override anchor is a full
        -- anchor link {target, side, offsets}: the child snaps flush to that side
        -- of its target through the exact fallback pipeline -- absolute UIParent-
        -- space side-snap math, growth-edge pin, child-local conversion, dim-aware
        -- pixel snap, idempotent guard and child cascade.
        function CludesUI._TryOverrideAnchor(childKey, childBar)
            if LM.isUnlocked then
                return false
            end
            local groupId = ActiveGidFor(childKey)
            if not groupId then
                engagedKeys[childKey] = nil
                return false
            end
            local shade = Store()[childKey][groupId]
            if type(shade) ~= "table" or not shade.target then
                -- Malformed entry (no target): never hold the element hostage.
                engagedKeys[childKey] = nil
                return false
            end
            engagedKeys[childKey] = groupId
            childBar = childBar or LM.GetBarFrame(childKey)
            if not childBar then
                return true
            end
            if InCombatLockdown() and childBar:IsProtected() then
                CludesUI._AnchorPark.Park(childKey)
                return true
            end
            local tgt = LM.GetBarFrame(shade.target)
            if not tgt or not tgt:GetLeft() then
                -- Target unavailable (absent frame / no bounds yet): hold position.
                return true
            end
            local side = shade.side
            local uiS = UIParent:GetEffectiveScale()
            local tS = tgt:GetEffectiveScale()
            local cS = childBar:GetEffectiveScale()
            local tL = (tgt:GetLeft() or 0) * tS / uiS
            local tR = (tgt:GetRight() or 0) * tS / uiS
            local tT = (tgt:GetTop() or 0) * tS / uiS
            local tB = (tgt:GetBottom() or 0) * tS / uiS
            local tCX = (tL + tR) / 2
            local tCY = (tT + tB) / 2
            -- Growth-edge extent applies to the override target too.
            if CludesUI._GetAnchorTargetExtent then
                local ext = CludesUI._GetAnchorTargetExtent(shade.target, side)
                if ext then
                    if side == "TOP" then
                        tT = ext
                    elseif side == "BOTTOM" then
                        tB = ext
                    elseif side == "LEFT" then
                        tL = ext
                    elseif side == "RIGHT" then
                        tR = ext
                    end
                end
            end
            local cW = (childBar:GetWidth() or 50) * cS / uiS
            local cH = (childBar:GetHeight() or 50) * cS / uiS
            local cx, cy
            if side == "LEFT" then
                cx, cy = tL - cW / 2, tCY
            elseif side == "RIGHT" then
                cx, cy = tR + cW / 2, tCY
            elseif side == "TOP" then
                cx, cy = tCX, tT + cH / 2
            elseif side == "BOTTOM" then
                cx, cy = tCX, tB - cH / 2
            else
                cx, cy = tCX, tCY
            end
            -- User-set offsets relative to the side-snap point (ghost drags).
            cx = cx + (shade.offsetX or 0)
            cy = cy + (shade.offsetY or 0)
            -- Keep the growth-fixed edge pinned on the cross axis (inert for
            -- center-growth / non-bar children), like the fallback apply.
            local gsx, gsy = CludesUI._FallbackGrowShift(childKey, side, cW, cH)
            cx = cx + gsx
            cy = cy + gsy
            -- Temporary per-target visual shift (e.g. "Shift Elements if No
            -- Resource/Power"), mirroring the main anchor path.
            if CludesUI._GetAnchorTargetShiftDir then
                local dir, extraY = CludesUI._GetAnchorTargetShiftDir(shade.target, childKey)
                if dir ~= 0 then
                    cy = cy + dir * ((tT - tB) + (extraY or 0))
                end
            end
            local acRatio = uiS / cS
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
            -- Children anchored to THIS element must follow it to the override spot.
            LM._pendingAnchorKeys[childKey] = "all"
            ScheduleAnchorBatch()
            return true
        end

        -- Repaint one released element through its normal owners: the module's
        -- own apply, then the unlock anchor link when one exists (a one-key
        -- mirror of the centralized pass).
        local function RepaintStandard(childKey)
            local elem = registeredElements[childKey]
            if elem and elem.applyPosition then
                pcall(elem.applyPosition, childKey)
            end
            if
                CludesUI.IsUnlockAnchored
                and CludesUI.IsUnlockAnchored(childKey)
                and CludesUI.ReapplyUnlockAnchor
            then
                CludesUI.ReapplyUnlockAnchor(childKey)
            end
        end

        -- Engage/disengage sweep for unlock open/close and combat suspend/resume:
        -- every stored element re-tries (idempotent); keys the try released
        -- repaint through their normal owners.
        function CludesUI._ReapplyOverrideAnchors()
            local storage = Store()
            local released
            for childKey in pairs(engagedKeys) do
                released = released or {}
                released[childKey] = true
            end
            if storage then
                for childKey in pairs(storage) do
                    if CludesUI._TryOverrideAnchor(childKey) and released then
                        released[childKey] = nil
                    end
                end
            end
            if released then
                for childKey in pairs(released) do
                    engagedKeys[childKey] = nil
                    RepaintStandard(childKey)
                end
            end
        end

        -- Store the override link (target + side) for one group, chosen through
        -- the same element pick mode as regular anchoring. Re-picking the SAME
        -- target keeps the dragged offsets (only the side changed); a new target
        -- resets them, exactly like re-anchoring invalidates a fallback.
        function CludesUI._SetOverrideAnchor(childKey, groupId, targetKey, side)
            if not childKey or not groupId or not targetKey or targetKey == childKey then
                return
            end
            local storage = Store(true)
            if not storage then
                return
            end
            local ent = storage[childKey]
            if not ent then
                ent = {}
                storage[childKey] = ent
            end
            local prev = ent[groupId]
            local keepOff = type(prev) == "table" and prev.target == targetKey
            ent[groupId] = {
                target = targetKey,
                side = side or "BOTTOM",
                offsetX = keepOff and prev.offsetX or nil,
                offsetY = keepOff and prev.offsetY or nil,
            }
            LM.hasChanges = true
            if CludesUI._RefreshOverrideGhosts then
                CludesUI._RefreshOverrideGhosts()
            end
        end

        -- Enter element pick mode for an override anchor target: same flow as
        -- anchoring; the mover click dispatcher reads the pending group id.
        function CludesUI._BeginOverrideAnchorPick(mover, groupId)
            if not mover or not groupId then
                return
            end
            CancelPickMode()
            LM.pickMode = "overrideAnchor"
            LM.pickModeMover = mover
            ovPickGid = groupId
            if mover._showPickText then
                mover._showPickText("Click any element\nto set as the Override Anchor")
            end
            FadeOverlayForSelectElement(true)
        end

        function CludesUI._OverridePickGid()
            return ovPickGid
        end

        -- Every stored override target for an element (any group) -- the pick
        -- handler's cycle walk expands through these edges.
        function CludesUI._OverrideAnchorTargets(childKey)
            local storage = Store()
            local ent = storage and storage[childKey]
            if not ent then
                return nil
            end
            local result
            for _, shade in pairs(ent) do
                if type(shade) == "table" and shade.target then
                    result = result or {}
                    result[#result + 1] = shade.target
                end
            end
            return result
        end

        -- Elements currently RIDING an engaged override anchor on parentKey --
        -- PropagateAnchorChain re-applies them when that target moves/resizes.
        function CludesUI._OverrideAnchorRiders(parentKey)
            if not next(engagedKeys) then
                return nil
            end
            local storage = Store()
            if not storage then
                return nil
            end
            local result
            for childKey, groupId in pairs(engagedKeys) do
                local ent = storage[childKey]
                local shade = ent and ent[groupId]
                if type(shade) == "table" and shade.target == parentKey then
                    result = result or {}
                    result[#result + 1] = childKey
                end
            end
            return result
        end

        function CludesUI._ClearOverrideAnchor(childKey, groupId)
            local storage = Store()
            local ent = storage and storage[childKey]
            if ent then
                ent[groupId] = nil
                if not next(ent) then
                    storage[childKey] = nil
                end
            end
            LM.hasChanges = true
            if CludesUI._RefreshOverrideGhosts then
                CludesUI._RefreshOverrideGhosts()
            end
        end

        ---------------------------------------------------------------------------
        --  Override anchor ghosts (MakeGhostSet): every stored entry gets a ghost
        --  with a gold tint, labeled "<element>: <group>", sitting where the
        --  element lands while that group's override is engaged. Dragging it
        --  writes the stored offsets; the real mover always edits the baseline.
        ---------------------------------------------------------------------------
        -- Gold identity tint (matches the override gold-border language, and
        -- distinguishes these from the accent-tinted fallback ghosts).
        local OV_R, OV_G, OV_B = 0.95, 0.78, 0.25

        local function GhostPos(g)
            local storage = Store()
            local ent = storage and storage[g._childKey]
            local shade = ent and ent[g._gid]
            if type(shade) ~= "table" or not shade.target then
                return nil
            end
            return shade
        end

        local set = MakeGhostSet({
            getLink = GhostPos,
            init = function(g, childKey, groupId)
                g._childKey = childKey
                g._gid = groupId
                g:SetSize(120, 16)
                return OV_R, OV_G, OV_B, OV_R, OV_G, OV_B
            end,
            label = function(g, fontStr)
                g._lblFS = fontStr
                g._lblName = GroupName(g._gid) or ""
                fontStr:SetText((LM.GetBarLabel(g._childKey) or g._childKey) .. ": " .. g._lblName)
            end,
            -- Group renames refresh lazily here (throttled by the caller).
            onSync = function(g)
                local gname = GroupName(g._gid)
                if gname and gname ~= g._lblName and g._lblFS then
                    g._lblName = gname
                    g._lblFS:SetText((LM.GetBarLabel(g._childKey) or g._childKey) .. ": " .. gname)
                end
            end,
            deselectOther = "_DeselectFallbackGhosts",
        })
        local ghosts = set.ghosts

        CludesUI._HideOverrideGhosts = set.HideAll
        CludesUI._SetOverrideGhostsAlpha = set.SetAlpha
        CludesUI._DeselectOverrideGhosts = set.Deselect
        CludesUI._ClearOverrideGhostTempHides = set.ClearTempHides
        CludesUI._NudgeSelectedOverrideGhost = set.Nudge

        function CludesUI._RefreshOverrideGhosts()
            if not LM.isUnlocked or not LM.unlockFrame then
                CludesUI._HideOverrideGhosts()
                return
            end
            local storage = Store()
            -- Hygiene: entries for deleted groups are dead (fail-open at engage);
            -- prune them here so ghosts and exports stay clean. Unlock-only cost.
            if storage then
                local valid = {}
                for _, g in ipairs(Groups() or {}) do
                    valid[g.id] = true
                end
                for ck, ent in pairs(storage) do
                    for groupId, shade in pairs(ent) do
                        if not valid[groupId] or type(shade) ~= "table" or not shade.target then
                            ent[groupId] = nil
                        end
                    end
                    if not next(ent) then
                        storage[ck] = nil
                    end
                end
            end
            for _, g in pairs(ghosts) do
                if not GhostPos(g) then
                    set.Hide(g)
                end
            end
            if not storage then
                return
            end
            for ck, ent in pairs(storage) do
                for groupId in pairs(ent) do
                    local gk = ck .. "|" .. tostring(groupId)
                    local g = ghosts[gk]
                    if not g then
                        g = set.Create(ck, groupId)
                        ghosts[gk] = g
                    end
                    set.Sync(g)
                end
            end
        end
    end

    -- True when an action bar's clamped frame touches a screen edge (or its rect
    -- cannot be read): the engine may be holding it there, so its live rect can be
    -- the clamped spot rather than the one its saved position asks for (the bars
    -- are clamped for display only and keep their saved spot even off screen).
    -- Automatic captures that bank live geometry into saved data skip such a bar
    -- and retry on a later pass; explicit user moves (drag, nudge, link changes)
    -- still capture it. Every other element, and a bar not yet clamped, is false.
    CludesUI._RectHeldByClamp = function(key, f)
        local abKeys = CludesUI._abBarKeys
        if not (abKeys and abKeys[key]) then
            return false
        end
        if not (f and f:IsClampedToScreen()) then
            return false
        end
        local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
        if not (l and r and t and b) then
            return true
        end
        if
            issecretvalue
            and (issecretvalue(l) or issecretvalue(r) or issecretvalue(t) or issecretvalue(b))
        then
            return true
        end
        local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local wid, hgt = UIParent:GetSize()
        return l * s <= 0.5 or b * s <= 0.5 or r * s >= wid - 0.5 or t * s >= hgt - 0.5
    end

    -- Captures the growth-edge pin for an anchored custom-growth bar from LIVE  -- cui-style: allow comment-budget
    -- geometry: which target reference edge the fixed growth edge hangs off
    -- (refX/refY = LEFT|RIGHT|TOP|BOTTOM|CENTER) and its offset from that edge
    -- (edgeOffX/edgeOffY). Movement-free by construction -- the pin reproduces the
    -- bar's current on-screen position exactly. refFor records the grow direction it
    -- was captured for, so anchors with no pin and grow-direction changes recapture
    -- on the next apply. Reference choice: a side on the growth axis pins to that
    -- side's target edge (honoring the growth-edge extent override); a perpendicular
    -- side pins to the near edge, chosen once by which half of the target the fixed
    -- edge sits in, so runtime straddling can never flip it.
    CludesUI._unlockCaptureGrowPin = function(childKey, ai, side)
        if not ai or not ai.target then
            return false
        end
        if ai.mode == "POINT" then
            return false
        end
        local childBar = LM.GetBarFrame(childKey)
        local targetBar = LM.GetBarFrame(ai.target)
        if not childBar or not targetBar then
            return false
        end
        if not (childBar:GetLeft() and targetBar:GetLeft()) then
            return false
        end
        local growDir = GetBarGrowDirActual(childKey)
        if not growDir or growDir == "CENTER" then
            return false
        end
        local uiS = UIParent:GetEffectiveScale()
        local cS = childBar:GetEffectiveScale()
        local tS = targetBar:GetEffectiveScale()
        local snapF = (CludesUI.PP and CludesUI.PP.Snap)
            or function(val)
                return math.floor(val + 0.5)
            end
        local tL = (targetBar:GetLeft() or 0) * tS / uiS
        local tR = (targetBar:GetRight() or 0) * tS / uiS
        local tT = (targetBar:GetTop() or 0) * tS / uiS
        local tB = (targetBar:GetBottom() or 0) * tS / uiS
        if CludesUI._GetAnchorTargetExtent then
            local ext = CludesUI._GetAnchorTargetExtent(ai.target, side)
            if ext then
                if side == "TOP" then
                    tT = ext
                elseif side == "BOTTOM" then
                    tB = ext
                elseif side == "LEFT" then
                    tL = ext
                elseif side == "RIGHT" then
                    tR = ext
                end
            end
        end
        local tCX, tCY = (tL + tR) / 2, (tT + tB) / 2
        if growDir == "LEFT" or growDir == "RIGHT" then
            local fixedX = ((growDir == "RIGHT") and childBar:GetLeft() or childBar:GetRight()) * cS / uiS
            local refX
            if side == "LEFT" then
                refX = "LEFT"
            elseif side == "RIGHT" then
                refX = "RIGHT"
            -- A screen edge spans the full width: hold against the screen's horizontal
            -- center like every other element on that edge, not its left or right.
            elseif CludesUI.IsScreenEdgeKey(ai.target) then
                refX = "CENTER"
            else
                refX = (fixedX < tCX) and "LEFT" or "RIGHT"
            end
            local refVal = (refX == "LEFT" and tL) or (refX == "RIGHT" and tR) or tCX
            ai.refX = refX
            ai.edgeOffX = snapF(fixedX - refVal)
            ai.refY, ai.edgeOffY = nil, nil
        else
            local fixedY = ((growDir == "UP") and childBar:GetBottom() or childBar:GetTop()) * cS / uiS
            local refY
            if side == "TOP" then
                refY = "TOP"
            elseif side == "BOTTOM" then
                refY = "BOTTOM"
            -- A screen edge spans the full height: hold against the screen's vertical
            -- center like every other element on that edge, not its top or bottom.
            elseif CludesUI.IsScreenEdgeKey(ai.target) then
                refY = "CENTER"
            else
                refY = (fixedY < tCY) and "BOTTOM" or "TOP"
            end
            local refVal = (refY == "TOP" and tT) or (refY == "BOTTOM" and tB) or tCY
            ai.refY = refY
            ai.edgeOffY = snapF(fixedY - refVal)
            ai.refX, ai.edgeOffX = nil, nil
        end
        ai.refFor = growDir
        return true
    end

    -- ApplyAnchorPosition owns an anchored element's position, leaving an element
    -- with its own positional contribution (RaidFrames' per-tier offset) nowhere to
    -- apply it. A getter registered here folds it into the computed position instead
    -- of correcting afterwards, which would defeat the idempotent guard below and reposition the anchor every pass forever.
    local function ExtraAnchorOffset(childKey)
        local t = CludesUI._anchorExtraOffset
        local func = t and t[childKey]
        if not func then
            return 0, 0
        end
        local success, dx, dy = pcall(func, childKey)
        if not success or type(dx) ~= "number" or type(dy) ~= "number" then
            return 0, 0
        end
        return dx, dy
    end
    -- On CludesUI for CreateMover's cog menu (Lua 5.1 limit: 60 upvalues).
    CludesUI._ExtraAnchorOffset = ExtraAnchorOffset

    -- A screen edge governs exactly one axis: left/right hold X, top/bottom hold Y.
    -- That is what lets an element carry two anchors -- the primary one (an element or
    -- a screen edge) keeps whichever axis no ai.edge claims. Returns "X", "Y" or nil.
    CludesUI._ScreenEdgeAxis = function(key)
        if key == "SCREEN_LEFT" or key == "SCREEN_RIGHT" then
            return "X"
        end
        if key == "SCREEN_TOP" or key == "SCREEN_BOTTOM" then
            return "Y"
        end
        return nil
    end

    -- Offsets for a link, read from the live rects the way a drag does: near edge on
    -- the anchored side, center on the cross axis. The element's own extra offset (the
    -- raid container's per-tier offset) comes out, because every anchored apply folds
    -- it back in. Returns nil when either rect is missing.
    CludesUI._CaptureAnchorOffsets = function(childKey, targetKey, side)
        local details = GetAnchorInfo(childKey)
        if details and details.mode == "POINT" and details.target == targetKey then
            return mod.PointAnchors.Capture(childKey, details)
        end
        local child, tgt = LM.GetBarFrame(childKey), LM.GetBarFrame(targetKey)
        if not (child and child:GetLeft() and tgt and tgt:GetLeft()) then
            return nil
        end
        local uiS = UIParent:GetEffectiveScale()
        local cS, tS = child:GetEffectiveScale() / uiS, tgt:GetEffectiveScale() / uiS
        local exX, exY = ExtraAnchorOffset(childKey)
        exX, exY = exX * cS, exY * cS
        local cL, cR = child:GetLeft() * cS - exX, child:GetRight() * cS - exX
        local cT, cB = child:GetTop() * cS - exY, child:GetBottom() * cS - exY
        local tL, tR = tgt:GetLeft() * tS, tgt:GetRight() * tS
        local tT, tB = tgt:GetTop() * tS, tgt:GetBottom() * tS
        local cCX, cCY = (cL + cR) / 2, (cT + cB) / 2
        local tCX, tCY = (tL + tR) / 2, (tT + tB) / 2
        if side == "LEFT" then
            return cR - tL, cCY - tCY
        end
        if side == "RIGHT" then
            return cL - tR, cCY - tCY
        end
        if side == "TOP" then
            return cCX - tCX, cB - tT
        end
        if side == "BOTTOM" then
            return cCX - tCX, cT - tB
        end
        return cCX - tCX, cCY - tCY
    end

    -- Screen-edge marker: a line along the edge itself, so picking a side in the cog
    -- menu shows WHERE the element will hold. Hovering a row previews it, a click
    -- flashes it. The textures hang on the unlock overlay and are reused, so they exist
    -- only while unlock mode is open.
    CludesUI._ShowScreenEdgeMarker = function(edgeKey, flash)
        if not LM.unlockFrame then
            return
        end
        local storage = CludesUI._screenEdgeMarkers
        if not storage then
            storage = {}
            CludesUI._screenEdgeMarkers = storage
        end
        -- Own host frame in the top strata: on the unlock overlay itself the line went
        -- behind every bar and frame that sits in a higher strata. It is a child of the
        -- overlay, so it still disappears with unlock mode.
        local host = storage.host
        if not host then
            host = CreateFrame("Frame", nil, LM.unlockFrame)
            host:SetFrameStrata("TOOLTIP")
            host:SetFrameLevel(400)
            host:SetAllPoints(UIParent)
            storage.host = host
        end
        host:Show()
        local m = storage[edgeKey]
        if not m then
            local vertical = (edgeKey == "SCREEN_LEFT" or edgeKey == "SCREEN_RIGHT")
            local thick = (Pix and Pix.mult or 1) * 5
            m = host:CreateTexture(nil, "OVERLAY")
            if m.SetSnapToPixelGrid then
                m:SetSnapToPixelGrid(false)
                m:SetTexelSnappingBias(0)
            end
            m:SetColorTexture(1, 0.7, 0.3, 0.9)
            if vertical then
                m:SetWidth(thick)
                local corner = (edgeKey == "SCREEN_LEFT") and "LEFT" or "RIGHT"
                m:SetPoint("TOP", UIParent, "TOP" .. corner, 0, 0)
                m:SetPoint("BOTTOM", UIParent, "BOTTOM" .. corner, 0, 0)
            else
                m:SetHeight(thick)
                local edge = (edgeKey == "SCREEN_TOP") and "TOP" or "BOTTOM"
                m:SetPoint("LEFT", UIParent, edge .. "LEFT", 0, 0)
                m:SetPoint("RIGHT", UIParent, edge .. "RIGHT", 0, 0)
            end
            storage[edgeKey] = m
        end
        m:Show()
        if flash then
            if m._hideTimer then
                m._hideTimer:Cancel()
            end
            m._hideTimer = C_Timer.NewTimer(0.8, function()
                m._hideTimer = nil
                m:Hide()
            end)
        end
    end

    -- Hover preview only: a flash owns the marker until its timer fires.
    CludesUI._HideScreenEdgeMarker = function(edgeKey)
        local storage = CludesUI._screenEdgeMarkers
        local m = storage and storage[edgeKey]
        if m and not m._hideTimer then
            m:Hide()
        end
    end

    -- The single number a cross-axis screen edge needs: the capture above, reduced to
    -- the axis that edge governs.
    CludesUI._CaptureScreenEdgeOffset = function(childKey, edgeKey, side)
        local offX, offY = CludesUI._CaptureAnchorOffsets(childKey, edgeKey, side)
        if offX == nil then
            return nil
        end
        return (CludesUI._ScreenEdgeAxis(edgeKey) == "X") and offX or offY
    end

    -- Anchor-target shift providers ("Shift Elements if No Resource" and kin):  -- cui-style: allow comment-budget
    -- modules register (targetKey, childKey) -> dir, extraY functions; the public
    -- CludesUI._GetAnchorTargetShiftDir the apply paths consult dispatches to
    -- them, first non-zero answer wins (each provider returns 0 for foreign keys).
    -- A LIST, not a single slot: ResourceBars (ERB_* bars) and CooldownManager
    -- (TBBG_* tracking-bar global groups) both provide. Companion enter/exit hooks
    -- ride the same registration: `wants` = a shift WOULD apply outside unlock mode
    -- (unlock entry un-shifts before snapshotting -- deliberately ignores unlock
    -- state), `restore` = re-apply after unlock closes (PropagateAnchorChain is a
    -- no-op while unlocked).
    -- or-preserve + self-seeding registration (modules push directly instead of
    -- calling an API): providers must register with ZERO load-order coupling --
    -- whichever file runs first creates the shared list, exactly like the
    -- _anchorExtraOffset registry and this file's own _unlockRegisteredElements.
    CludesUI._anchorShiftProviders = CludesUI._anchorShiftProviders or {}
    -- pcall-isolated: one provider erroring must not take the OTHER module's
    -- anchoring (or unlock entry) down with it.
    CludesUI._GetAnchorTargetShiftDir = function(targetKey, childKey)
        local t = CludesUI._anchorShiftProviders
        for idx = 1, #t do
            local success, dir, extraY = pcall(t[idx].dir, targetKey, childKey)
            if success and dir and dir ~= 0 then
                return dir, extraY
            end
        end
        return 0
    end
    function CludesUI.AnchorShiftWantsApply()
        local t = CludesUI._anchorShiftProviders
        for idx = 1, #t do
            local wid = t[idx].wants
            if wid then
                local success, wants = pcall(wid)
                if success and wants then
                    return true
                end
            end
        end
        return false
    end
    function CludesUI.RestoreAnchorShifts()
        local t = CludesUI._anchorShiftProviders
        for idx = 1, #t do
            local r = t[idx].restore
            if r then
                pcall(r)
            end
        end
    end
    -- Optional `enter` hooks: run at unlock entry (and combat resume) BEFORE
    -- positions are snapshotted, for providers whose visual adjustment lives
    -- outside the anchor system (e.g. CDM's Additional Bar Offset repositions
    -- UN-anchored bars) -- the anchored side is covered by the wants-gated
    -- ReapplyAllUnlockAnchors strip. Each hook self-gates, so providers with
    -- nothing active cost one function call.
    function CludesUI.RunAnchorShiftEnters()
        local t = CludesUI._anchorShiftProviders
        for idx = 1, #t do
            local e = t[idx].enter
            if e then
                pcall(e)
            end
        end
    end

    LM.ApplyAnchorPosition = function(childKey, targetKey, side, noMark, noMove, fromCascade)
        -- A screen edge is a fixed target, never a child: a stray link from bad data
        -- would re-point its strip and skew every screen-edge link.
        if CludesUI.IsScreenEdgeKey(childKey) then
            return
        end
        local childBar = LM.GetBarFrame(childKey)
        local targetBar = LM.GetBarFrame(targetKey)
        if not childBar then
            return
        end
        -- Addon owns this element's position (e.g. a grouped Tracking Bar member
        -- chained to its group anchor): never reposition it, or its relative SetPoint to the anchor gets clobbered, in or out of combat.
        local cElem = registeredElements[childKey]
        if cElem and cElem.isAnchored and cElem.isAnchored(childKey) then
            return
        end
        -- The module alone places this frame from its saved spot (ownsPosition: main
        -- chat): a link would be a third owner beside it and Blizzard's Edit Mode.
        if cElem and cElem.ownsPosition then
            return
        end
        if PositionHeld(childKey) then
            return
        end
        -- Override anchor (opt-in, Resource Bars): while a spec-override group's
        -- stored position is engaged it owns this element outright -- it wins over
        -- the anchor link exactly like it wins over the saved position.
        if CludesUI._TryOverrideAnchor and CludesUI._TryOverrideAnchor(childKey, childBar) then
            return
        end
        -- Fallback anchor (opt-in): a target configured away on this spec (no frame) or
        -- a pet frame with no pet positions the child at its stored fallback instead of leaving it wherever the default build put it.
        if
            CludesUI._TryFallbackAnchor
            and CludesUI._TryFallbackAnchor(childKey, targetKey, childBar, targetBar)
        then
            return
        end
        if not targetBar then
            return
        end
        -- Skip protected child frames during combat (action bars); reading target
        -- bounds stays safe even for a protected target (oUF), SetPoint is only called
        -- on the child. Park the key so the anchor reapplies when combat drops.
        if InCombatLockdown() and childBar:IsProtected() then
            CludesUI._AnchorPark.Park(childKey)
            return
        end

        -- No valid target screen bounds (hidden/not yet laid out): bail rather than
        -- compute garbage coordinates that oscillate. Same for the child under noMove, which reads its actual position.
        local tL0 = targetBar:GetLeft()
        -- A target hanging off an engine aura container (a Blizzard Style cast bar
        -- under its frame's aura stack) has secret edges under aura restriction:
        -- no compare or arithmetic may touch them. Park until regen.
        if issecretvalue and issecretvalue(tL0) then
            CludesUI._AnchorPark.Park(childKey)
            return
        end
        if not tL0 then
            return
        end
        if noMove then
            -- A child on a follow anchor reports a secret rect: it cannot "stay
            -- put" (nothing may read where it is), so it is placed absolutely
            -- instead -- unlock mode keeps the follow provider inert, so that is
            -- its resting spot, which the movers can read.
            local cl0 = childBar:GetLeft()
            if issecretvalue and issecretvalue(cl0) then
                noMove = false
            elseif not cl0 then
                return
            end
        end

        local uiS = UIParent:GetEffectiveScale()
        local tS = targetBar:GetEffectiveScale()
        local cS = childBar:GetEffectiveScale()

        -- Get target center in UIParent space
        local tL = (targetBar:GetLeft() or 0) * tS / uiS
        local tR = (targetBar:GetRight() or 0) * tS / uiS
        local tT = (targetBar:GetTop() or 0) * tS / uiS
        local tB = (targetBar:GetBottom() or 0) * tS / uiS
        local tCX = (tL + tR) / 2
        local tCY = (tT + tB) / 2

        -- Growth-edge extent: when the anchored side matches the target group's growth
        -- direction, the edge follows the outermost visible member (top of the topmost
        -- bar of an upward-growing tracking bar group). Provider returns nil for every
        -- other target/side (keeping the frame's own bounds); cross-axis centering stays on the anchor frame.
        if CludesUI._GetAnchorTargetExtent then
            local ext = CludesUI._GetAnchorTargetExtent(targetKey, side)
            if ext then
                if side == "TOP" then
                    tT = ext
                elseif side == "BOTTOM" then
                    tB = ext
                elseif side == "LEFT" then
                    tL = ext
                elseif side == "RIGHT" then
                    tR = ext
                end
            end
        end

        -- Get child size in UIParent space (a child riding an engine aura
        -- container reads back secret under aura restriction: park until regen).
        local cW0, cH0 = childBar:GetWidth(), childBar:GetHeight()
        if issecretvalue and (issecretvalue(cW0) or issecretvalue(cH0)) then
            -- Unlock mode: a child still hanging off a followed edge (the unit's
            -- live aura stack when unlock opened with a target up) is placed at
            -- its absolute resting spot below, which frees its rect, so its
            -- stored size stands in for the unreadable one. Parking here would
            -- wait for a regen that never comes out of combat, leaving the bar
            -- on the stack and its mover unsized.
            local elem = LM.isUnlocked and registeredElements[childKey]
            local gw, gh
            if elem and elem.getSize then
                gw, gh = elem.getSize(childKey)
            end
            if type(gw) ~= "number" or type(gh) ~= "number" or issecretvalue(gw) or issecretvalue(gh) then
                CludesUI._AnchorPark.Park(childKey)
                return
            end
            cW0, cH0 = gw, gh
        end
        local cW = (cW0 or 50) * cS / uiS
        local cH = (cH0 or 50) * cS / uiS

        -- Compute child center
        local cx, cy
        local ai = GetAnchorInfo(childKey)
        if ai and ai.mode == "POINT" then
            cx, cy = mod.PointAnchors.Center(childKey, childBar, ai, targetBar, cW, cH)
            if not cx then
                return
            end
        elseif ai and ai.offsetX ~= nil and ai.offsetY ~= nil then
            -- Edge-to-edge offset mode: the offset runs from the child's near edge to
            -- the target's anchor edge, so a resized child keeps that near edge fixed.
            local edgeX, edgeY
            if side == "LEFT" then
                edgeX = tL
                edgeY = tCY
                cx = edgeX + ai.offsetX - cW / 2
                cy = edgeY + ai.offsetY
            elseif side == "RIGHT" then
                edgeX = tR
                edgeY = tCY
                cx = edgeX + ai.offsetX + cW / 2
                cy = edgeY + ai.offsetY
            elseif side == "TOP" then
                edgeX = tCX
                edgeY = tT
                cx = edgeX + ai.offsetX
                cy = edgeY + ai.offsetY + cH / 2
            elseif side == "BOTTOM" then
                edgeX = tCX
                edgeY = tB
                cx = edgeX + ai.offsetX
                cy = edgeY + ai.offsetY - cH / 2
            else
                edgeX = tCX
                edgeY = tCY
                cx = edgeX + ai.offsetX
                cy = edgeY + ai.offsetY
            end
        else
            -- Side-snap mode (initial placement or legacy)
            if side == "LEFT" then
                cx = tL - cW / 2
                cy = tCY
            elseif side == "RIGHT" then
                cx = tR + cW / 2
                cy = tCY
            elseif side == "TOP" then
                cx = tCX
                cy = tT + cH / 2
            elseif side == "BOTTOM" then
                cx = tCX
                cy = tB - cH / 2
            else
                cx = tCX
                cy = tCY
            end
            -- Store the computed offset edge-to-edge, pixel-snapped. Skip when valid
            -- offsets exist: recomputing from live bounds accumulates float drift every login.
            if ai and (ai.offsetX == nil or ai.offsetY == nil) then
                local snap = (CludesUI and CludesUI.PP and CludesUI.PP.Snap)
                    or function(val)
                        return math.floor(val + 0.5)
                    end
                local edgeX, edgeY
                if side == "LEFT" then
                    edgeX = tL
                    edgeY = tCY
                    ai.offsetX = snap((cx + cW / 2) - edgeX)
                    ai.offsetY = snap(cy - edgeY)
                elseif side == "RIGHT" then
                    edgeX = tR
                    edgeY = tCY
                    ai.offsetX = snap((cx - cW / 2) - edgeX)
                    ai.offsetY = snap(cy - edgeY)
                elseif side == "TOP" then
                    edgeX = tCX
                    edgeY = tT
                    ai.offsetX = snap(cx - edgeX)
                    ai.offsetY = snap((cy - cH / 2) - edgeY)
                elseif side == "BOTTOM" then
                    edgeX = tCX
                    edgeY = tB
                    ai.offsetX = snap(cx - edgeX)
                    ai.offsetY = snap((cy + cH / 2) - edgeY)
                else
                    edgeX = tCX
                    edgeY = tCY
                    ai.offsetX = snap(cx - edgeX)
                    ai.offsetY = snap(cy - edgeY)
                end
            end
        end

        -- CDM/AB bars with a non-CENTER growth direction use edge-based SetPoint so
        -- SetSize grows from the fixed edge. Edge preservation (overriding cx/cy with
        -- the saved/live edge) applies ONLY to UNANCHORED bars whose own size changed:
        -- anchored bars always use the target-computed cx/cy (target bounds + offsets
        -- are authoritative; saved-edge data may be stale).
        local cdmEdgeAnchor
        local isCdmOrAB = not (ai and ai.mode == "POINT")
            and (childKey:sub(1, 4) == "CDM_" or (CludesUI._abBarKeys and CludesUI._abBarKeys[childKey]))
        local isCDM = childKey:sub(1, 4) == "CDM_"

        -- Unified growth-edge pin (anchored custom-growth bars): the bar's fixed  -- cui-style: allow comment-budget
        -- growth edge holds a stored offset from a LIVE target reference edge -- one
        -- formula for login, cascade, save and revert, with no saved-edge duality, no
        -- follow baselines and no mode flags. Engages only once the anchor's offsets
        -- exist (a fresh anchor's first apply side-snaps; the follow-up batch apply
        -- captures the pin from the placed position). Anchors without a pin and
        -- grow-direction changes recapture lazily and movement-free from the bar's
        -- current position; while frames lack bounds the legacy pin below still
        -- applies, so early-login frames degrade gracefully.
        local growPinned = false
        if isCdmOrAB and ai and ai.target and ai.offsetX ~= nil and ai.offsetY ~= nil then
            local gd = GetBarGrowDirActual(childKey)
            if gd and gd ~= "CENTER" then
                -- Lazy capture ONLY at provable quiescence: the settle pass (trusted by
                -- session-baseline/bless captures) or inside an unlock session. CDM bars
                -- populate icons asynchronously at login; capturing mid-population would
                -- freeze a transient half-icon edge into the pin. Until capture, the legacy pin below serves the apply.
                -- Never from a clamp-held rect: the pin would bank the clamped spot.
                if
                    ai.refFor ~= gd
                    and CludesUI._unlockCaptureGrowPin
                    and (CludesUI._settleReapplyInProgress or LM.isUnlocked)
                    and not CludesUI._RectHeldByClamp(childKey, childBar)
                    and not CludesUI._RectHeldByClamp(targetKey, targetBar)
                then
                    CludesUI._unlockCaptureGrowPin(childKey, ai, side)
                end
                if ai.refFor == gd then
                    if gd == "LEFT" or gd == "RIGHT" then
                        local refVal = (ai.refX == "LEFT" and tL) or (ai.refX == "RIGHT" and tR) or tCX
                        local fixedX = refVal + (ai.edgeOffX or 0)
                        cx = (gd == "RIGHT") and (fixedX + cW / 2) or (fixedX - cW / 2)
                        cdmEdgeAnchor = (gd == "RIGHT") and "LEFT" or "RIGHT"
                    else
                        local refVal = (ai.refY == "TOP" and tT) or (ai.refY == "BOTTOM" and tB) or tCY
                        local fixedY = refVal + (ai.edgeOffY or 0)
                        cy = (gd == "UP") and (fixedY + cH / 2) or (fixedY - cH / 2)
                        cdmEdgeAnchor = (gd == "UP") and "BOTTOM" or "TOP"
                    end
                    growPinned = true
                end
            end
        end
        -- The edge-anchor/edge-preservation path is normally suppressed in unlock mode
        -- so movers capture the user's live (center-based) drag positions.
        -- _reapplyForceEdgePreserve is a narrow exception: the shift-unapply reapply on
        -- unlock entry (OpenUnlockMode) repositions anchored bars to their TRUE saved
        -- positions, and a custom-growth bar's true position is its fixed growth edge --
        -- without it those bars paint centered all session. Set only around that reapply, so manual drag/drop is unaffected.
        if
            not growPinned
            and isCdmOrAB
            and (not LM.isUnlocked or CludesUI._reapplyForceEdgePreserve)
            and (isCDM or childKey == "StanceBar" or not CludesUI._applyingSavedPositions)
        then
            local growDir = GetBarGrowDirActual(childKey)
            if growDir and growDir ~= "CENTER" then
                -- Always set cdmEdgeAnchor so SetPoint uses the fixed edge
                if growDir == "RIGHT" then
                    cdmEdgeAnchor = "LEFT"
                elseif growDir == "LEFT" then
                    cdmEdgeAnchor = "RIGHT"
                elseif growDir == "DOWN" then
                    cdmEdgeAnchor = "TOP"
                elseif growDir == "UP" then
                    cdmEdgeAnchor = "BOTTOM"
                end
                -- Edge preservation: override cx/cy with the saved/live edge so the fixed  -- cui-style: allow comment-budget
                -- growth edge stays put when the bar's OWN width changes (e.g. a class
                -- with a different stance-button/cooldown count). Skipped ONLY on a
                -- runtime cascade (fromCascade=true): there the TARGET moved/resized, so
                -- the bar must follow via the center offset and the absolute saved edge
                -- is stale. On init/Save&Exit reapply (fromCascade=nil) the whole chain
                -- is at its saved positions, so the width-independent saved edge is
                -- authoritative, keeping the growth edge fixed across characters and
                -- stopping the dw/2 layout nudge from shifting the bar on save/reload.
                -- StanceBar anchors to the player frame (fixed), so its saved edge is never stale even on cascade -- always honor it.
                local anchorDB2 = GetAnchorDB()
                local hasAnchorTarget = anchorDB2 and anchorDB2[childKey] and anchorDB2[childKey].target
                -- Force the clean target-relative offset (skip live-edge preservation)
                -- also when a temporary anchor-target shift is active (ERB "Shift
                -- Elements if No Resource/Power"): otherwise the own-re-apply reads the
                -- already-shifted live bounds and the injection below adds the shift a
                -- second time -> continuous drift. Provider returns 0 for non-shift targets, so this is a no-op elsewhere.
                local shiftActive = not LM.isUnlocked
                    and CludesUI._GetAnchorTargetShiftDir
                    and CludesUI._GetAnchorTargetShiftDir(targetKey, childKey) ~= 0
                -- Anchored CDM growth bars position from their absolute saved growth  -- cui-style: allow comment-budget
                -- edge (savedEdge.x/.y, override block below). On login that's a PURE
                -- absolute pin reading nothing live: the follow delta (dTX/dTY below)
                -- holds at 0 until _anchorFollowReady flips (post-settle debounce, once
                -- the chain stops resizing). After the flip the absolute edge shifts by
                -- how far the anchor target moved since save, so the bar FOLLOWS a
                -- target that relocates at runtime (spec change sliding the player
                -- frame); a same-spec login computes ~0 delta at the flip, so the
                -- pin->follow handoff is invisible. ERB-shift bars use the follow
                -- center; StanceBar and unanchored bars keep their own absolute-edge
                -- path; AB growth bars keep cascade-follow via `not isCDM` -- all compute delta 0.
                local skipEdgePreserve = (hasAnchorTarget and childKey ~= "StanceBar")
                    and (shiftActive or (fromCascade and not isCDM))
                if not skipEdgePreserve then
                    local cScale = childBar:GetEffectiveScale()
                    local ratio = cScale / uiS
                    local savedEdge
                    if isCDM and CludesUI._cdmBarPositions then
                        local sp = CludesUI._cdmBarPositions[childKey:sub(5)]
                        if sp then
                            savedEdge = sp
                        end
                    elseif childKey == "StanceBar" and CludesUI._abBarPositions then
                        local sp = CludesUI._abBarPositions[childKey]
                        if sp then
                            savedEdge = sp
                        end
                    end
                    -- Follow: shift the absolute saved growth edge by how far the anchor  -- cui-style: allow comment-budget
                    -- target moved/resized SINCE this bar was saved. When the anchor side
                    -- aligns with the bar's own growth direction (anchored to the
                    -- target's RIGHT while itself growing RIGHT), the saved growth edge
                    -- IS the near edge facing the target, so the saved target edge
                    -- recovers as (savedNearEdge - ai.offsetX/Y) and diffs against the
                    -- target's CURRENT edge -- tracking the target moving AND resizing (a
                    -- center-delta can't detect a CENTER-anchored bar that only changes
                    -- width). Misaligned anchors, or no ai.offsetX/Y yet, fall back to the
                    -- center-delta (correct for non-resizing targets: unit frames, ERB
                    -- bars). Gated on _anchorFollowReady (false until the post-settle
                    -- flip, so the whole login is a pure absolute pin) and a saved
                    -- baseline existing. CDM growth bars only; StanceBar, ERB-shift bars and unlock mode keep the pure absolute pin (delta 0).
                    local uw, uh = UIParent:GetSize()
                    local dTX, dTY = 0, 0
                    -- StanceBar joins the follow-delta path: its "always pin, never
                    -- follow" design assumed a fixed anchor target (player frame), but it
                    -- can be anchored to a resizing CDM/AB bar. Its baseline
                    -- (savedEdge.tgt*) is captured only at unlock Save (EAB savePos); until a re-save the fields are nil and every delta below stays 0.
                    if
                        (isCDM or childKey == "StanceBar")
                        and not shiftActive
                        and not LM.isUnlocked
                        and CludesUI._anchorFollowReady
                        and savedEdge
                    then
                        -- Corner-follow engages when the target's size is driven by a
                        -- content-sized bar: the target is itself a CDM bar, or its
                        -- matched axis rides an unbroken width/height match chain ending
                        -- at a CDM/action bar. Any other target keeps the center-delta path.
                        local targetIsCDM = targetKey and targetKey:sub(1, 4) == "CDM_"
                        -- Resolve the follow baseline: the saved baseline (tgt*, captured  -- cui-style: allow comment-budget
                        -- by savePos at unlock Save & Exit) wins. When absent, fall back to
                        -- a SESSION baseline captured during a settle pass (chain is
                        -- quiescent, this child is provably at its pin, so pairing is
                        -- exact -- delta 0 at capture by construction). Runtime-only, never
                        -- persisted, auto-invalidated when the saved edge/target changes
                        -- (unlock re-save, profile/spec swap) -> pure pin until the next
                        -- settle recaptures. Gives intra-session follow with no re-save,
                        -- while cross-session (no saved baseline) stays a login pin.
                        local bTgtx, bTgty = savedEdge.tgtx, savedEdge.tgty
                        local bTgtL, bTgtR = savedEdge.tgtL, savedEdge.tgtR
                        local bTgtT, bTgtB = savedEdge.tgtT, savedEdge.tgtB
                        if bTgtx == nil and bTgty == nil then
                            local rt = CludesUI._anchorRtBaseline
                            local b = rt and rt[childKey]
                            if b and (b.sx ~= savedEdge.x or b.sy ~= savedEdge.y or b.tgt ~= targetKey) then
                                rt[childKey] = nil
                                b = nil
                            end
                            if
                                not b
                                and CludesUI._settleReapplyInProgress
                                and not CludesUI._RectHeldByClamp(targetKey, targetBar)
                            then
                                b = {
                                    sx = savedEdge.x,
                                    sy = savedEdge.y,
                                    tgt = targetKey,
                                    tgtx = tCX,
                                    tgty = tCY,
                                    tgtL = tL,
                                    tgtR = tR,
                                    tgtT = tT,
                                    tgtB = tB,
                                }
                                if not rt then
                                    rt = {}
                                    CludesUI._anchorRtBaseline = rt
                                end
                                rt[childKey] = b
                            end
                            if b then
                                bTgtx, bTgty = b.tgtx, b.tgty
                                bTgtL, bTgtR = b.tgtL, b.tgtR
                                bTgtT, bTgtB = b.tgtT, b.tgtB
                            end
                        end
                        if ai and ai.offsetX ~= nil and savedEdge.x then
                            local childEdgeX = (uw / 2 + savedEdge.x) * ratio
                            if side == "RIGHT" and growDir == "RIGHT" then
                                dTX = tR - (childEdgeX - ai.offsetX)
                            elseif side == "LEFT" and growDir == "LEFT" then
                                dTX = tL - (childEdgeX - ai.offsetX)
                            elseif
                                (targetIsCDM or MatchH.ChainDrivenToBar(targetKey, "width"))
                                and (side == "TOP" or side == "BOTTOM")
                                and (growDir == "RIGHT" or growDir == "LEFT")
                                and bTgtL
                                and bTgtR
                                and bTgtx
                            then
                                -- Corner case: anchored to the target's TOP/BOTTOM edge
                                -- while growing horizontally. Hold against the target's
                                -- NEAR horizontal edge (picked by which side of the target
                                -- center the bar sits) so the corner survives a target
                                -- WIDTH change -- a center delta is 0 for a center-anchored
                                -- resize. Idempotent: reads only saved data + the target's
                                -- live edge, never the child's own position.
                                if childEdgeX < bTgtx then
                                    dTX = tL - bTgtL
                                else
                                    dTX = tR - bTgtR
                                end
                            elseif childKey == "StanceBar" and side == "LEFT" and bTgtL then
                                -- Opposite-grow side anchor (snapped to target's LEFT while
                                -- growing RIGHT): near-edge recovery can't apply (saved
                                -- growth edge is the FAR edge), so track the snapped-to edge.
                                dTX = tL - bTgtL
                            elseif childKey == "StanceBar" and side == "RIGHT" and bTgtR then
                                dTX = tR - bTgtR
                            elseif bTgtx then
                                dTX = tCX - bTgtx
                            end
                        elseif bTgtx then
                            dTX = tCX - bTgtx
                        end
                        if ai and ai.offsetY ~= nil and savedEdge.y then
                            local childEdgeY = (uh / 2 + savedEdge.y) * ratio
                            if side == "TOP" and growDir == "UP" then
                                dTY = tT - (childEdgeY - ai.offsetY)
                            elseif side == "BOTTOM" and growDir == "DOWN" then
                                dTY = tB - (childEdgeY - ai.offsetY)
                            elseif
                                (targetIsCDM or MatchH.ChainDrivenToBar(targetKey, "height"))
                                and (side == "LEFT" or side == "RIGHT")
                                and (growDir == "UP" or growDir == "DOWN")
                                and bTgtT
                                and bTgtB
                                and bTgty
                            then
                                -- Corner case: anchored to target's LEFT/RIGHT edge while
                                -- growing vertically. Hold against target's NEAR vertical edge so the corner survives a target HEIGHT change.
                                if childEdgeY < bTgty then
                                    dTY = tB - bTgtB
                                else
                                    dTY = tT - bTgtT
                                end
                            elseif childKey == "StanceBar" and side == "TOP" and bTgtT then
                                -- Opposite-grow side anchor, vertical symmetric case.
                                dTY = tT - bTgtT
                            elseif childKey == "StanceBar" and side == "BOTTOM" and bTgtB then
                                dTY = tB - bTgtB
                            elseif bTgty then
                                dTY = tCY - bTgty
                            end
                        elseif bTgty then
                            dTY = tCY - bTgty
                        end
                    end
                    if growDir == "RIGHT" then
                        if savedEdge and savedEdge.point == "LEFT" and savedEdge.x then
                            cx = (uw / 2 + savedEdge.x) * ratio + cW / 2 + dTX
                        else
                            local fL = childBar:GetLeft()
                            if fL then
                                cx = fL * ratio + cW / 2
                            end
                        end
                    elseif growDir == "LEFT" then
                        if savedEdge and savedEdge.point == "RIGHT" and savedEdge.x then
                            cx = (uw / 2 + savedEdge.x) * ratio - cW / 2 + dTX
                        else
                            local fR = childBar:GetRight()
                            if fR then
                                cx = fR * ratio - cW / 2
                            end
                        end
                    elseif growDir == "DOWN" then
                        if savedEdge and savedEdge.point == "TOP" and savedEdge.y then
                            cy = (uh / 2 + savedEdge.y) * ratio - cH / 2 + dTY
                        else
                            local fT = childBar:GetTop()
                            if fT then
                                cy = fT * ratio - cH / 2
                            end
                        end
                    elseif growDir == "UP" then
                        if savedEdge and savedEdge.point == "BOTTOM" and savedEdge.y then
                            cy = (uh / 2 + savedEdge.y) * ratio + cH / 2 + dTY
                        else
                            local fB = childBar:GetBottom()
                            if fB then
                                cy = fB * ratio + cH / 2
                            end
                        end
                    end
                elseif
                    hasAnchorTarget
                    and not shiftActive
                    and CludesUI._abBarKeys
                    and CludesUI._abBarKeys[childKey]
                    and childKey ~= "StanceBar"
                    and CludesUI._abBarPositions
                then
                    -- Corner-follow for an action bar grow child anchored across a target
                    -- whose matched axis is chain-driven to a content-sized bar. Keeps the
                    -- edge-offset cascade position above for every non-corner case; only the
                    -- perpendicular growth-edge coordinate is re-derived, from the bar's own
                    -- saved edge plus the persisted target baseline, to hold it against the moving near edge.
                    local sp = CludesUI._abBarPositions[childKey]
                    if sp then
                        local ratio = childBar:GetEffectiveScale() / uiS
                        local uw, uh = UIParent:GetSize()
                        if
                            (side == "TOP" or side == "BOTTOM")
                            and (growDir == "LEFT" or growDir == "RIGHT")
                            and sp.x
                            and sp.tgtx
                            and sp.tgtL
                            and sp.tgtR
                            and MatchH.ChainDrivenToBar(targetKey, "width")
                        then
                            local childEdgeX = (uw / 2 + sp.x) * ratio
                            local dTX
                            if childEdgeX < sp.tgtx then
                                dTX = tL - sp.tgtL
                            else
                                dTX = tR - sp.tgtR
                            end
                            if growDir == "LEFT" and sp.point == "RIGHT" then
                                cx = (uw / 2 + sp.x) * ratio - cW / 2 + dTX
                            elseif growDir == "RIGHT" and sp.point == "LEFT" then
                                cx = (uw / 2 + sp.x) * ratio + cW / 2 + dTX
                            end
                        elseif
                            (side == "LEFT" or side == "RIGHT")
                            and (growDir == "UP" or growDir == "DOWN")
                            and sp.y
                            and sp.tgty
                            and sp.tgtT
                            and sp.tgtB
                            and MatchH.ChainDrivenToBar(targetKey, "height")
                        then
                            local childEdgeY = (uh / 2 + sp.y) * ratio
                            local dTY
                            if childEdgeY < sp.tgty then
                                dTY = tB - sp.tgtB
                            else
                                dTY = tT - sp.tgtT
                            end
                            if growDir == "DOWN" and sp.point == "TOP" then
                                cy = (uh / 2 + sp.y) * ratio - cH / 2 + dTY
                            elseif growDir == "UP" and sp.point == "BOTTOM" then
                                cy = (uh / 2 + sp.y) * ratio + cH / 2 + dTY
                            end
                        end
                    end
                end
            end
        end

        -- Cross-axis screen-edge anchor: a screen edge that holds ONE axis while the
        -- primary anchor keeps the other (raid frames on the minimap, but pinned to the
        -- top edge). Authoritative on its axis, so it runs after the growth-edge pin and
        -- the edge-preservation paths, which all read the PRIMARY target.
        if ai and ai.edge and ai.edge.key then
            local eFrame = LM.GetBarFrame(ai.edge.key)
            local eAxis = CludesUI._ScreenEdgeAxis(ai.edge.key)
            if eFrame and eFrame:GetLeft() and eAxis then
                local eS = eFrame:GetEffectiveScale() / uiS
                local eOff = ai.edge.offset or 0
                if eAxis == "X" then
                    local ref = ((ai.edge.side == "RIGHT") and eFrame:GetRight() or eFrame:GetLeft()) * eS
                    cx = (ai.edge.side == "RIGHT") and (ref + eOff + cW / 2) or (ref + eOff - cW / 2)
                else
                    local ref = ((ai.edge.side == "TOP") and eFrame:GetTop() or eFrame:GetBottom()) * eS
                    cy = (ai.edge.side == "TOP") and (ref + eOff + cH / 2) or (ref + eOff - cH / 2)
                end
            end
        end

        -- Temporary per-target visual shift (e.g. ResourceBars "Shift Elements if No
        -- Resource"). Applied to the final computed center only, never written to the
        -- saved ai.offsetX/offsetY. Magnitude is the target's live UIParent-space
        -- height (tT - tB), staying scale-correct. Provider returns 0 while unlock mode is active (and nil/0 until a feature opts in).
        if not LM.isUnlocked and CludesUI._GetAnchorTargetShiftDir then
            -- extraY (optional 2nd return) tunes magnitude by N pixels in the shift direction; nil/0 keeps bar-height-only behavior.
            local dir, extraY = CludesUI._GetAnchorTargetShiftDir(targetKey, childKey)
            if dir ~= 0 then
                cy = cy + dir * ((tT - tB) + (extraY or 0))
            end
        end

        -- Convert child center to CENTER-relative offset for centralized positioning
        local uiW, uiH = UIParent:GetSize()
        local centerX = cx - uiW / 2
        local centerY = cy - uiH / 2
        -- Declared at function scope on purpose: the pendingPositions write at the end
        -- of this function reads them, and it sits outside the branch below that
        -- computes them. Kept local, they were read as (never set) globals there.
        local bCenterX, bCenterY
        -- Follow provider (opt-in): a frame the child anchors to instead of taking
        -- an absolute position, for a target edge the engine moves (see the branch below).
        local follow
        if side == "BOTTOM" and CludesUI._GetAnchorFollowFrame then
            follow = CludesUI._GetAnchorFollowFrame(childKey, targetKey, side)
        end

        -- Only move the actual bar frame when noMove is not set
        if not noMove then
            local acRatio = uiS / cS

            if ai and ai.mode == "POINT" then
                local changed
                bCenterX, bCenterY, changed =
                    mod.PointAnchors.Place(childKey, childBar, ai, centerX, centerY, cW0, cH0)
                if not bCenterX then
                    return
                end
                if changed then
                    LM._pendingAnchorKeys[childKey] = "all"
                    ScheduleAnchorBatch()
                end
            elseif cdmEdgeAnchor then
                -- Non-CENTER-grow bar: position at the growth edge directly so
                -- SetSize grows naturally without any post-resize re-anchoring.
                local bEdgeX, bEdgeY
                if cdmEdgeAnchor == "LEFT" then
                    bEdgeX = (centerX - (cW / 2)) * acRatio
                    bEdgeY = centerY * acRatio
                elseif cdmEdgeAnchor == "RIGHT" then
                    bEdgeX = (centerX + (cW / 2)) * acRatio
                    bEdgeY = centerY * acRatio
                elseif cdmEdgeAnchor == "TOP" then
                    bEdgeX = centerX * acRatio
                    bEdgeY = (centerY + (cH / 2)) * acRatio
                elseif cdmEdgeAnchor == "BOTTOM" then
                    bEdgeX = centerX * acRatio
                    bEdgeY = (centerY - (cH / 2)) * acRatio
                end
                -- Snap to the physical pixel grid: the GROWTH-axis coordinate is a frame
                -- EDGE -> whole-pixel snap; the PERPENDICULAR coordinate is the frame's
                -- CENTER on that axis -> parity-aware snap (SnapCenterForDim), since an
                -- odd-pixel child dimension needs a half-pixel center for both edges to
                -- land whole (else odd-height/width anchored CDM bars shift half a pixel: cooldown swipes bleeding past borders).
                local PPa = CludesUI and CludesUI.PP
                if PPa and PPa.SnapForES then
                    local childW2 = childBar:GetWidth() or 0
                    local childH2 = childBar:GetHeight() or 0
                    if cdmEdgeAnchor == "LEFT" or cdmEdgeAnchor == "RIGHT" then
                        bEdgeX = PPa.SnapForES(bEdgeX, cS)
                        bEdgeY = PPa.SnapCenterForDim and PPa.SnapCenterForDim(bEdgeY, childH2, cS)
                            or PPa.SnapForES(bEdgeY, cS)
                    else
                        bEdgeY = PPa.SnapForES(bEdgeY, cS)
                        bEdgeX = PPa.SnapCenterForDim and PPa.SnapCenterForDim(bEdgeX, childW2, cS)
                            or PPa.SnapForES(bEdgeX, cS)
                    end
                end
                -- Element-contributed offset (RaidFrames' per-tier offset), folded in
                -- BEFORE the idempotent guard so the guard still converges: it's part of the target position, not a correction after settling.
                local exDX, exDY = ExtraAnchorOffset(childKey)
                bEdgeX, bEdgeY = bEdgeX + exDX, bEdgeY + exDY
                local skip = false
                local okPt, anchorPoint, relTo, relPoint, curX, curY = pcall(childBar.GetPoint, childBar, 1)
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
                if okPt and anchorPoint == cdmEdgeAnchor and relPoint == "CENTER" and relTo == UIParent then
                    local onePx = ((Pix and Pix.perfect) or 1) / cS
                    -- Sub-pixel tolerance only: identical recomputes differ by float dust,
                    -- never real fractions. Must stay BELOW half a pixel or the parity-aware
                    -- perpendicular snap above (a legitimate 0.5px correction on dimension parity change) gets skipped, leaving half-pixel edges.
                    local tol = onePx * 0.25
                    if
                        curX
                        and curY
                        and math.abs(curX - bEdgeX) <= tol
                        and math.abs(curY - bEdgeY) <= tol
                    then
                        skip = true
                    end
                end
                if not skip then
                    pcall(function()
                        CludesUI.ClearFramePoints(childBar)
                        CludesUI.SetFramePoint(childBar, cdmEdgeAnchor, UIParent, "CENTER", bEdgeX, bEdgeY)
                    end)
                    LM._pendingAnchorKeys[childKey] = "all"
                    ScheduleAnchorBatch()
                end
            elseif follow then
                -- Follow frame: the child hangs off a frame whose edge the engine
                -- moves -- a Blizzard Style unit frame's aura block, whose bottom
                -- rides the aura stack. Under aura restriction that geometry is a
                -- secret value no Lua may read, so the centre math above is
                -- expressed as an offset from the frame's own BOTTOM point (the
                -- provider's static edge is where that point rests with nothing
                -- stacked) and the engine does the following. The saved position
                -- stays the resting one.
                local PPa = CludesUI and CludesUI.PP
                local exFX, exFY = ExtraAnchorOffset(childKey)
                -- Resting centre, snapped and offset exactly like the CENTER branch
                -- (it is what CommitPositions may read for this element).
                bCenterX = centerX * acRatio
                bCenterY = centerY * acRatio
                if PPa and PPa.SnapCenterForDim then
                    bCenterX = PPa.SnapCenterForDim(bCenterX, cW0 or 0, cS)
                    bCenterY = PPa.SnapCenterForDim(bCenterY, cH0 or 0, cS)
                end
                bCenterX, bCenterY = bCenterX + exFX, bCenterY + exFY
                local fx = (cx - tCX) * acRatio
                local fy = ((cy + cH / 2) - tB) * acRatio
                if PPa and PPa.SnapForES then
                    fx = PPa.SnapForES(fx, cS)
                    fy = PPa.SnapForES(fy, cS)
                end
                fx, fy = fx + exFX, fy + exFY
                local skip = false
                local okPt, anchorPoint, relTo, relPoint, curX, curY = pcall(childBar.GetPoint, childBar, 1)
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
                if okPt and anchorPoint == "TOP" and relPoint == "BOTTOM" and relTo == follow then
                    local onePx = ((Pix and Pix.perfect) or 1) / cS
                    local tol = onePx * 0.5
                    if curX and curY and math.abs(curX - fx) < tol and math.abs(curY - fy) < tol then
                        skip = true
                    end
                end
                if not skip then
                    pcall(function()
                        CludesUI.ClearFramePoints(childBar)
                        CludesUI.SetFramePoint(childBar, "TOP", follow, "BOTTOM", fx, fy)
                    end)
                    LM._pendingAnchorKeys[childKey] = "all"
                    ScheduleAnchorBatch()
                end
            else
                -- Standard CENTER positioning for all other elements
                bCenterX = centerX * acRatio
                bCenterY = centerY * acRatio
                -- Snap the center FIRST (dim-aware for odd-pixel frames) so the idempotent
                -- skip below compares curX/curY (already snapped) against the value
                -- actually SetPoint'd. Snapping AFTER the check meant a bar whose snap
                -- offset exceeds the 0.5px tolerance never matched (curX snapped, bCenter
                -- not), so it re-SetPoint the same value every frame while sitting still.
                local PPa = CludesUI and CludesUI.PP
                if PPa and PPa.SnapCenterForDim then
                    -- The size read above (the stored one when the live rect was
                    -- secret: the bar is still on its followed edge until the SetPoint below).
                    bCenterX = PPa.SnapCenterForDim(bCenterX, cW0 or 0, cS)
                    bCenterY = PPa.SnapCenterForDim(bCenterY, cH0 or 0, cS)
                end
                local exCX, exCY = ExtraAnchorOffset(childKey)
                bCenterX, bCenterY = bCenterX + exCX, bCenterY + exCY
                -- Idempotent guard: skip SetPoint when the bar is already at this exact
                -- position (sub-physical-pixel tolerance). Kills flicker when multiple cascade passes compute the same answer (steady state).
                local skip = false
                local okPt, anchorPoint, relTo, relPoint, curX, curY = pcall(childBar.GetPoint, childBar, 1)
                -- A child still on a followed edge (unlock opened with its unit's
                -- aura stack up) reads its anchor back secret: never compared.
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
                    local onePx = ((Pix and Pix.perfect) or 1) / cS
                    local tol = onePx * 0.5
                    if
                        curX
                        and curY
                        and math.abs(curX - bCenterX) < tol
                        and math.abs(curY - bCenterY) < tol
                    then
                        skip = true
                    end
                end
                if not skip then
                    pcall(function()
                        CludesUI.ClearFramePoints(childBar)
                        CludesUI.SetFramePoint(childBar, "CENTER", UIParent, "CENTER", bCenterX, bCenterY)
                    end)
                    LM._pendingAnchorKeys[childKey] = "all"
                    ScheduleAnchorBatch()
                end
            end
        else
            -- noMove: bar stays put, but resync ai.offsetX/offsetY from its actual screen position so future propagation uses correct offsets
            -- A followed edge (see the follow branch above): the child sits under
            -- the live edge, so the offset is measured from it, not the resting one.
            -- Read only while plain (unlock mode never runs under aura restriction).
            if follow then
                local fbB = follow:GetBottom()
                if not (issecretvalue and issecretvalue(fbB)) and fbB then
                    tB = fbB * follow:GetEffectiveScale() / uiS
                end
            end
            local bS = childBar:GetEffectiveScale()
            local bL = (childBar:GetLeft() or 0) * bS / uiS
            local bR = (childBar:GetRight() or 0) * bS / uiS
            local bT = (childBar:GetTop() or 0) * bS / uiS
            local bB = (childBar:GetBottom() or 0) * bS / uiS
            local actualCX = (bL + bR) / 2
            local actualCY = (bT + bB) / 2
            -- Skip offset recomputation if valid offsets already exist -- recomputing from live bounds introduces floating point drift.
            if ai and ai.mode == "POINT" and (ai.offsetX == nil or ai.offsetY == nil) then
                ai.offsetX, ai.offsetY = mod.PointAnchors.Capture(childKey, ai, childBar, targetBar)
            elseif ai and (ai.offsetX == nil or ai.offsetY == nil) then
                local actualHW = (bR - bL) / 2
                local actualHH = (bT - bB) / 2
                local snap = (CludesUI and CludesUI.PP and CludesUI.PP.Snap)
                    or function(val)
                        return math.floor(val + 0.5)
                    end
                if side == "LEFT" then
                    ai.offsetX = snap((actualCX + actualHW) - tL)
                    ai.offsetY = snap(actualCY - tCY)
                elseif side == "RIGHT" then
                    ai.offsetX = snap((actualCX - actualHW) - tR)
                    ai.offsetY = snap(actualCY - tCY)
                elseif side == "TOP" then
                    ai.offsetX = snap(actualCX - tCX)
                    ai.offsetY = snap((actualCY - actualHH) - tT)
                elseif side == "BOTTOM" then
                    ai.offsetX = snap(actualCX - tCX)
                    ai.offsetY = snap((actualCY + actualHH) - tB)
                else
                    ai.offsetX = snap(actualCX - tCX)
                    ai.offsetY = snap(actualCY - tCY)
                end
            end
        end

        -- Update mover position to match (CENTER anchor so hover-expand stays symmetric)
        local m = movers[childKey]
        if m then
            local mX, mY
            if noMove then
                -- Bar is already in its correct position -- read its actual screen coords
                local bS = childBar:GetEffectiveScale()
                local bL = (childBar:GetLeft() or 0) * bS / uiS
                local bR = (childBar:GetRight() or 0) * bS / uiS
                local bT = (childBar:GetTop() or 0) * bS / uiS
                local bB = (childBar:GetBottom() or 0) * bS / uiS
                mX = (bL + bR) / 2
                mY = ((bT + bB) / 2) - UIParent:GetHeight()
            else
                mX = cx
                mY = cy - UIParent:GetHeight()
                -- Followed edge: the bar sits under the live edge (plain outside
                -- restriction; the deferred re-anchor below corrects any rest).
                if follow then
                    local fbB = follow:GetBottom()
                    if not (issecretvalue and issecretvalue(fbB)) and fbB then
                        mY = mY + (fbB * follow:GetEffectiveScale() / uiS - tB)
                    end
                end
            end
            local PPp = CludesUI and CludesUI.PP
            if PPp then
                mX = PPp.Scale(mX)
                mY = PPp.Scale(mY)
            end
            m:ClearAllPoints()
            m:SetPoint("CENTER", UIParent, "TOPLEFT", mX, mY)
            if m._setCenterXY then
                m._setCenterXY(mX, mY)
            end
            -- Re-anchor mover to bar for pixel-perfect alignment
            if m.ReanchorToBar then
                m:ReanchorToBar()
            end
        end

        -- Store in pending positions only during unlock mode, so anchor-computed
        -- positions don't pollute saved positions at login.
        if not noMove and CludesUI._unlockActive then
            -- CDM/AB growth bars store edge-format positions, so writing CENTER coords
            -- here would overwrite the correct edge data on Save & Exit. Mark them
            -- anchored so CommitPositions uses snapshot/loadPos (edge format).
            local growSkip = false
            if isCdmOrAB then
                local gd = GetBarGrowDirActual(childKey)
                if gd and gd ~= "CENTER" then
                    growSkip = true
                end
            end
            if growSkip then
                pendingPositions[childKey] = { _anchored = true }
            else
                pendingPositions[childKey] = {
                    point = "CENTER",
                    relPoint = "CENTER",
                    x = bCenterX,
                    y = bCenterY,
                }
            end
        end
        if not noMark then
            LM.hasChanges = true
        end
    end

    -- Re-apply all saved anchor positions (called on open and after target moves)
    local function ReapplyAllAnchors()
        local saved = GetAnchorDB()
        if not saved then
            return
        end
        for childKey, details in pairs(saved) do
            if movers[childKey] and movers[details.target] then
                LM.ApplyAnchorPosition(childKey, details.target, details.side, true, true)
            end
        end
    end

    -- Recursively propagate anchor repositioning from a moved parent down the chain.
    -- visited guards circular anchor loops. changedAxis: "width", "height", or nil
    -- (nil = all axes, e.g. from a drag).
    LM.PropagateAnchorChain = function(parentKey, visited, changedAxis)
        visited = visited or {}
        if visited[parentKey] then
            return
        end
        visited[parentKey] = true
        local anchorDB = GetAnchorDB()
        if not anchorDB then
            return
        end
        -- Alias keys share the parent's physical frame (a global tracking bar group's
        -- TBBG_ key rides its anchor bar's TBB_ hooks): children anchored to the alias must cascade whenever the frame moves/resizes.
        local aliasKey = CludesUI._unlockKeyAliases and CludesUI._unlockKeyAliases[parentKey]
        if aliasKey and not visited[aliasKey] then
            LM.PropagateAnchorChain(aliasKey, visited, changedAxis)
        end
        for childKey, details in pairs(anchorDB) do
            local primaryMatch = (details.target == parentKey)
            -- A child reached only via its fallback link (a buff bar whose primary
            -- target is a TBB bar, fallback-anchored to Class Resource/Power) must also
            -- re-cascade when ITS fallback target moves/shifts, else it stays stale until the next full ReapplyAllUnlockAnchors pass (login/settle).
            local fallbackMatch = not primaryMatch
                and details.fallback
                and details.fallback.target == parentKey
            -- Cross-axis edge parents cascade unconditionally: the axis gate below reads
            -- info.side, which describes the PRIMARY link, not this edge.
            local edgeMatch = (not primaryMatch) and details.edge and details.edge.key == parentKey
            if primaryMatch or fallbackMatch or edgeMatch then
                -- Axis isolation: skip children on the unaffected axis. A resize leaves a  -- cui-style: allow comment-budget
                -- perpendicular-anchored child unaffected ONLY when the target's center is
                -- invariant on the changed axis (true for CENTER growth, but an edge-fixed
                -- growth direction moves the center: LEFT/RIGHT growth shifts center-X on
                -- a width change, UP/DOWN shifts center-Y on a height change), so a
                -- TOP/BOTTOM-side child's X, tied to that center (edgeX = tCX in
                -- ApplyAnchorPosition), MUST reposition. Un-dominated (must cascade): a
                -- CDM/AB parent growing along the changed axis; a CDM/action-bar child
                -- whose parent's changed axis is match-chain-driven by a content-sized bar
                -- (corner-follow needs the same-tick cascade); a plain AB grow child of a
                -- still-dominated CDM/chain-driven parent. Every other child keeps the
                -- original gate. fallbackMatch skips this entirely: info.side describes the
                -- PRIMARY anchor's geometry, meaningless for the fallback's own math.
                local dominated = false
                if primaryMatch and details.mode ~= "POINT" and changedAxis == "width" then
                    dominated = (details.side == "TOP" or details.side == "BOTTOM")
                    if dominated then
                        if
                            parentKey:sub(1, 4) == "CDM_"
                            or (CludesUI._abBarKeys and CludesUI._abBarKeys[parentKey])
                        then
                            local tg = GetBarGrowDirActual(parentKey)
                            if tg == "LEFT" or tg == "RIGHT" then
                                dominated = false
                            end
                        elseif
                            (
                                childKey:sub(1, 4) == "CDM_"
                                or (CludesUI._abBarKeys and CludesUI._abBarKeys[childKey])
                            )
                            and MatchH.ChainDrivenToBar(parentKey, "width")
                        then
                            dominated = false
                        end
                        if
                            dominated
                            and CludesUI._abBarKeys
                            and CludesUI._abBarKeys[childKey]
                            and childKey ~= "StanceBar"
                            and MatchH.ChainDrivenToBar(parentKey, "width")
                        then
                            dominated = false
                        end
                    end
                elseif primaryMatch and details.mode ~= "POINT" and changedAxis == "height" then
                    dominated = (details.side == "LEFT" or details.side == "RIGHT")
                    if dominated then
                        if
                            parentKey:sub(1, 4) == "CDM_"
                            or (CludesUI._abBarKeys and CludesUI._abBarKeys[parentKey])
                        then
                            local tg = GetBarGrowDirActual(parentKey)
                            if tg == "UP" or tg == "DOWN" then
                                dominated = false
                            end
                        elseif
                            (
                                childKey:sub(1, 4) == "CDM_"
                                or (CludesUI._abBarKeys and CludesUI._abBarKeys[childKey])
                            )
                            and MatchH.ChainDrivenToBar(parentKey, "height")
                        then
                            dominated = false
                        end
                        if
                            dominated
                            and CludesUI._abBarKeys
                            and CludesUI._abBarKeys[childKey]
                            and childKey ~= "StanceBar"
                            and MatchH.ChainDrivenToBar(parentKey, "height")
                        then
                            dominated = false
                        end
                    end
                end
                if not dominated then
                    -- A follower re-placed from its saved link is no edit: the
                    -- drag, nudge or pick that moved its target marks the session.
                    LM.ApplyAnchorPosition(childKey, details.target, details.side, true, nil, true)
                    -- Do NOT call Sync() here: ApplyAnchorPosition already positions the mover; Sync() reads stale screen coords before WoW's layout pass, corrupting moverCX/moverCY.
                    LM.PropagateAnchorChain(childKey, visited, changedAxis)
                end
            end
        end
        -- Override-anchor riders with no anchor entry of their own follow their
        -- engaged target through the same cascade. Idempotent: the try only pokes
        -- the deferred batch (for THEIR children) when the frame actually moves.
        local ovRiders = CludesUI._OverrideAnchorRiders and CludesUI._OverrideAnchorRiders(parentKey)
        if ovRiders then
            for idx = 1, #ovRiders do
                local rk = ovRiders[idx]
                if not visited[rk] then
                    visited[rk] = true
                    CludesUI._TryOverrideAnchor(rk)
                end
            end
        end
    end

    -- Expose so child addons (CDM) can trigger anchor updates after resize.
    -- changedAxis: "width", "height", or nil (nil = propagate all axes)
    CludesUI.PropagateAnchorChain = function(key, changedAxis)
        local newAxis = changedAxis or "all"
        local existing = LM._pendingAnchorKeys[key]
        -- Merge axes: if different axes are pending, escalate to "all"
        if existing and existing ~= newAxis then
            LM._pendingAnchorKeys[key] = "all"
        else
            LM._pendingAnchorKeys[key] = newAxis
        end
        ScheduleAnchorBatch()
    end

    -- True if a given element key has an anchor relationship. ReloadFrames uses it to
    -- skip positioning anchored frames (the anchor system is their sole authority).
    CludesUI.IsAnchored = function(key)
        local adb = GetAnchorDB()
        if not adb then
            return false
        end
        local details = adb[key]
        return details and details.target and true or false
    end

    -- Synchronous self-anchor reapply: reposition an anchored element immediately (no
    -- deferred frame), removing the one-frame blink when a bar resizes and snaps back to its anchor edge.
    CludesUI.ReapplyOwnAnchor = function(key)
        -- Skip while this element's mover is being dragged: the drag OnUpdate owns positioning and reapplying would snap the bar back.
        local m = movers[key]
        if m and m._dragging then
            return
        end
        local anchorDB = GetAnchorDB()
        if not anchorDB then
            return
        end
        local details = anchorDB[key]
        if details and details.target then
            -- A rebuild or resize re-placing the element is no edit of the session.
            LM.ApplyAnchorPosition(key, details.target, details.side, true)
        end
    end

    -- Reapply ALL unlock-mode anchors. Called when a target frame moves so
    -- anchored children follow. Computes positions from anchor offsets.
    CludesUI.ReapplyAllUnlockAnchors = function()
        local adb = GetAnchorDB()
        if not adb then
            return
        end

        -- Apply in dependency order (roots first): pairs() is non-deterministic, so a
        -- chain A -> B -> C could process C before B, leaving C reading B's stale edges. Same pattern as ApplyMatchesInDependencyOrder.
        local depth = {}
        local function GetDepth(k, visiting)
            if depth[k] ~= nil then
                return depth[k]
            end
            if visiting[k] then
                depth[k] = 0
                return 0
            end -- cycle guard
            visiting[k] = true
            local details = adb[k]
            if details and details.target and adb[details.target] then
                depth[k] = 1 + GetDepth(details.target, visiting)
            else
                depth[k] = 0 -- target is a root (not in adb) or missing
            end
            visiting[k] = nil
            return depth[k]
        end

        local sequence = {}
        for childKey in pairs(adb) do
            GetDepth(childKey, {})
            sequence[#sequence + 1] = childKey
        end
        table.sort(sequence, function(a, b)
            return depth[a] < depth[b]
        end)

        for _, childKey in ipairs(sequence) do
            local details = adb[childKey]
            if
                details
                and details.target
                and LM.GetBarFrame(childKey)
                and (LM.GetBarFrame(details.target) or details.fallback ~= nil)
            then
                LM.ApplyAnchorPosition(childKey, details.target, details.side, true)
            end
        end

        -- No position persistence here: only Save & Exit (CommitPositions) writes,
        -- and no session mark: placing elements from their saved links edits nothing.
        wipe(pendingPositions)
    end

    -- Forced version of ReapplyAllUnlockAnchors: clears each child's points before  -- cui-style: allow comment-budget
    -- re-applying so ApplyAnchorPosition's idempotent guard can't perma-skip a stale
    -- cached answer. An anchored child (e.g. a CDM bar anchored to Class Resource) can
    -- settle 1px off when an upstream emission read transient bounds; once the cascade
    -- converges the guard sees "current matches stored" and never corrects. Manual
    -- un-anchor + re-anchor fixes it by forcing fresh evaluation against settled target
    -- bounds; this does the same without disturbing the DB. Wired into the CDM
    -- authoritative-pass trigger (ns._spellsReadyForApply) so it fires once at the same
    -- known-good moment used to retrigger width matches. Same dependency-sorted order; skips combat-protected children automatically.
    CludesUI.ReapplyAllUnlockAnchorsForced = function()
        local adb = GetAnchorDB()
        if not adb then
            return
        end

        local depth = {}
        local function GetDepth(k, visiting)
            if depth[k] ~= nil then
                return depth[k]
            end
            if visiting[k] then
                depth[k] = 0
                return 0
            end
            visiting[k] = true
            local details = adb[k]
            if details and details.target and adb[details.target] then
                depth[k] = 1 + GetDepth(details.target, visiting)
            else
                depth[k] = 0
            end
            visiting[k] = nil
            return depth[k]
        end

        local sequence = {}
        for childKey in pairs(adb) do
            GetDepth(childKey, {})
            sequence[#sequence + 1] = childKey
        end
        table.sort(sequence, function(a, b)
            return depth[a] < depth[b]
        end)

        local inCombat = InCombatLockdown()
        for _, childKey in ipairs(sequence) do
            local details = adb[childKey]
            if details and details.target then
                local childBar = LM.GetBarFrame(childKey)
                local targetBar = LM.GetBarFrame(details.target)
                local rcElem = registeredElements[childKey]
                if childBar and inCombat and childBar:IsProtected() then
                    CludesUI._AnchorPark.Park(childKey)
                end
                if
                    childBar
                    and (targetBar or details.fallback ~= nil)
                    and not (inCombat and childBar:IsProtected())
                    and not (rcElem and rcElem.isAnchored and rcElem.isAnchored(childKey))
                    and not (rcElem and rcElem.ownsPosition)
                    and not PositionHeld(childKey)
                then
                    -- AB growth bars: skip entirely -- applyPos from barPositions is
                    -- authoritative (edge format, width-independent, per LayoutBar).
                    local isABGrow = false
                    if
                        CludesUI._abBarKeys
                        and CludesUI._abBarKeys[childKey]
                        and childKey ~= "StanceBar"
                        and details.mode ~= "POINT"
                    then
                        local gd = GetBarGrowDirActual(childKey)
                        isABGrow = gd and gd ~= "CENTER"
                    end
                    if not isABGrow then
                        pcall(CludesUI.ClearFramePoints, childBar)
                        LM.ApplyAnchorPosition(childKey, details.target, details.side, true)
                    end
                end
            end
        end

        -- No position persistence here: only Save & Exit (CommitPositions) writes.
        wipe(pendingPositions)
    end

    -- UIParent-space center (x, y) of childKey's anchor target, computed identically to
    -- ApplyAnchorPosition's tCX/tCY so a captured value is directly comparable to the
    -- runtime target center. CDM savePos stores it as the follow baseline (sp.tgtx/.tgty). nil if no anchor target or no screen bounds.
    function CludesUI.GetAnchorTargetCenterUI(childKey)
        local adb = GetAnchorDB()
        local details = adb and adb[childKey]
        if not details or not details.target then
            return nil
        end
        local targetBar = LM.GetBarFrame(details.target)
        if not targetBar or not targetBar:GetLeft() then
            return nil
        end
        local uiS = UIParent:GetEffectiveScale()
        local tS = targetBar:GetEffectiveScale()
        local tL = (targetBar:GetLeft() or 0) * tS / uiS
        local tR = (targetBar:GetRight() or 0) * tS / uiS
        local tT = (targetBar:GetTop() or 0) * tS / uiS
        local tB = (targetBar:GetBottom() or 0) * tS / uiS
        return (tL + tR) / 2, (tT + tB) / 2
    end

    -- UIParent-space edges (left, right, top, bottom) of childKey's anchor target,
    -- computed identically to ApplyAnchorPosition's tL/tR/tT/tB. CDM/StanceBar savePos
    -- store them as sp.tgtL/.tgtR/.tgtT/.tgtB (follow baselines). Corner-follow gates on
    -- a CDM target, but StanceBar side-follow uses any target type, so edges are captured unconditionally. nil with no anchor target or screen bounds.
    function CludesUI.GetAnchorTargetEdgesUI(childKey)
        local adb = GetAnchorDB()
        local details = adb and adb[childKey]
        if not details or not details.target then
            return nil
        end
        local targetBar = LM.GetBarFrame(details.target)
        if not targetBar or not targetBar:GetLeft() then
            return nil
        end
        local uiS = UIParent:GetEffectiveScale()
        local tS = targetBar:GetEffectiveScale()
        local tL = (targetBar:GetLeft() or 0) * tS / uiS
        local tR = (targetBar:GetRight() or 0) * tS / uiS
        local tT = (targetBar:GetTop() or 0) * tS / uiS
        local tB = (targetBar:GetBottom() or 0) * tS / uiS
        return tL, tR, tT, tB
    end

    -- Resync anchor offsets from actual frame positions. Called AFTER a profile
    -- import/switch, once all frames sit at their absolute positions. Moves nothing: it
    -- reads current screen positions and recomputes offsets so anchors stay correct for
    -- future drags. Skips offsets that already have valid values -- reading live bounds adds floating-point noise (SetPoint->GetLeft round-trip) and drifts 1px.
    CludesUI.ResyncAnchorOffsets = function()
        local adb = GetAnchorDB()
        if not adb then
            return
        end
        for childKey, details in pairs(adb) do
            if details.target and LM.GetBarFrame(childKey) and LM.GetBarFrame(details.target) then
                -- Only resync offsets if they're missing (legacy data or first setup).
                -- Existing offsets from unlock mode are authoritative.
                if details.offsetX == nil or details.offsetY == nil then
                    LM.ApplyAnchorPosition(childKey, details.target, details.side, true, true)
                end
            end
        end
        -- Offset drift needs no override mirror: the layer harvest banks the live
        -- stores wholesale at every spec/profile transition.
        wipe(pendingPositions)
    end

    -------------------------------------------------------------------------------
    --  Saved position helpers
    -------------------------------------------------------------------------------
    LM.GetPositionDB = function()
        if not ABAR or not ABAR.db then
            return nil
        end
        if not ABAR.db.profile.barPositions then
            ABAR.db.profile.barPositions = {}
        end
        return ABAR.db.profile.barPositions
    end

    -------------------------------------------------------------------------------
    --  Centralized grow-direction position system
    --  All elements store positions as CENTER/CENTER (offset from UIParent center).
    --  On apply, the SetPoint anchor is picked by whether the element has an
    --  unlock-mode anchor relationship.
    -------------------------------------------------------------------------------

    -- Convert any anchor-point position to CENTER/CENTER format. Reads the frame's live
    -- screen bounds when possible; falls back to arithmetic conversion from the supplied coords + element size.
    local function ConvertToCenterPos(barId, anchorPoint, relPoint, posX, posY)
        local elem = registeredElements[barId]
        local widget = LM.GetBarFrame(barId)
        local uiW, uiH = UIParent:GetSize()
        local halfW, halfH = uiW / 2, uiH / 2

        -- If already CENTER/CENTER, pass through
        if anchorPoint == "CENTER" and relPoint == "CENTER" then
            return "CENTER", "CENTER", posX or 0, posY or 0
        end

        -- Try to read center from live frame (most accurate)
        if widget and widget:GetLeft() and widget:GetRight() and widget:GetTop() and widget:GetBottom() then
            local uiS = UIParent:GetEffectiveScale()
            local fS = widget:GetEffectiveScale()
            local ratio = fS / uiS
            local fL = widget:GetLeft() * ratio
            local fR = widget:GetRight() * ratio
            local fT = widget:GetTop() * ratio
            local fB = widget:GetBottom() * ratio
            local cx = (fL + fR) / 2 - halfW
            local cy = (fT + fB) / 2 - halfH
            return "CENTER", "CENTER", cx, cy
        end

        -- Arithmetic fallback: convert from the given anchor point using element size
        local ew, eh = 0, 0
        if elem and elem.getSize then
            ew, eh = elem.getSize(barId)
        elseif widget then
            ew = widget:GetWidth() or 0
            eh = widget:GetHeight() or 0
        end
        local hw, hh = (ew or 0) / 2, (eh or 0) / 2

        -- Convert stored coords to center-of-element in UIParent space
        local cx, cy
        if anchorPoint == "TOPLEFT" and (relPoint == "TOPLEFT" or relPoint == anchorPoint) then
            -- x,y are TOPLEFT offsets from UIParent TOPLEFT; center = (x + hw, y - hh)
            -- in TOPLEFT space -> CENTER space subtracts halfW, adds halfH (Y inverted)
            cx = posX + hw - halfW
            cy = posY - hh + halfH
        elseif anchorPoint == "LEFT" and relPoint == "CENTER" then
            -- CDM format: x is left-edge offset from center, y is center-Y offset
            cx = posX + hw
            cy = posY
        elseif anchorPoint == "RIGHT" and relPoint == "CENTER" then
            cx = posX - hw
            cy = posY
        elseif anchorPoint == "TOP" and relPoint == "CENTER" then
            cx = posX
            cy = posY - hh
        elseif anchorPoint == "BOTTOM" and relPoint == "CENTER" then
            cx = posX
            cy = posY + hh
        elseif relPoint == "CENTER" then
            -- Generic CENTER-relative: just use as-is for CENTER point
            cx = posX
            cy = posY
        else
            -- Unknown format: best-effort TOPLEFT assumption
            cx = (posX or 0) + hw - halfW
            cy = (posY or 0) - hh + halfH
        end

        return "CENTER", "CENTER", cx or 0, cy or 0
    end

    -- Apply a CENTER/CENTER position, choosing the SetPoint anchor from the element's
    -- unlock-mode anchor relationship: unanchored uses CENTER (grows centered on
    -- resize), anchored uses the edge opposite its anchor side (grows away from it).
    LM.ApplyCenterPosition = function(barId, place)
        if not place or place.point ~= "CENTER" or place.relPoint ~= "CENTER" then
            return false
        end
        -- Grouped bars and other addon-owned elements keep their relative anchors.
        local elem = registeredElements[barId]
        if elem and elem.isAnchored and elem.isAnchored(barId) then
            return true
        end
        local widget = LM.GetBarFrame(barId)
        if not widget then
            return false
        end
        if PositionHeld(barId) then
            return true
        end

        -- Skip elements anchored via the unlock anchor system -- their position
        -- is owned by ApplyAnchorPosition, not by the grow-direction logic here.
        local anchorDB = GetAnchorDB()
        local anchorInfo = anchorDB and anchorDB[barId]
        if anchorInfo and anchorInfo.target then
            return true
        end

        local cx, cy = place.x or 0, place.y or 0

        -- Stored coords are UIParent screen units (ConvertToCenterPos scales the frame's
        -- live edges into UIParent space), but SetPoint offsets are read in the FRAME's
        -- own space -- identical only while the frame sits at UIParent scale. An element
        -- that scales ITSELF would land at offset*scale, drifting toward/away from
        -- screen centre every apply, and Save & Exit would store the drifted spot.
        -- fRatio converts both ways and is exactly 1 for every unscaled element.
        local uiS = UIParent:GetEffectiveScale()
        local fS = widget:GetEffectiveScale() or uiS
        local fRatio = (uiS and uiS > 0 and fS and fS > 0) and (fS / uiS) or 1

        -- Determine grow anchor from unlock-mode anchor relationship
        local anchorInfo = anchorDB and anchorDB[barId]
        local anchor = "CENTER"
        local adjX, adjY = cx, cy

        if anchorInfo and anchorInfo.target and anchorInfo.side then
            local side = anchorInfo.side
            local fw = (widget:GetWidth() or 0) * fRatio
            local fh = (widget:GetHeight() or 0) * fRatio
            -- Raw half-dimensions (fw/2, fh/2), never floor(): for odd-pixel-height
            -- frames the center cy is integer+0.5, so cy +/- raw fh/2 lands back on integer pixels; floor(fh/2) would compute a half-pixel-off edge.
            if side == "LEFT" then
                anchor = "RIGHT"
                adjX = cx + fw / 2
            elseif side == "RIGHT" then
                anchor = "LEFT"
                adjX = cx - fw / 2
            elseif side == "TOP" then
                anchor = "BOTTOM"
                adjY = cy + fh / 2
            elseif side == "BOTTOM" then
                anchor = "TOP"
                adjY = cy - fh / 2
            end
        else
            -- No anchor relationship: pick the fixed edge from the grow direction.
            -- Prefer growEdge (width-independent absolute edge offset); fall back to CENTER +/- width/2 (width-dependent) only for positions without one.
            local ge = place.growEdge
            if ge and ge.anchor and ge.x and ge.y then
                anchor = ge.anchor
                adjX = ge.x
                adjY = ge.y
            else
                local growDir = GetBarGrowDirActual(barId)
                local fw = (widget:GetWidth() or 0) * fRatio
                local fh = (widget:GetHeight() or 0) * fRatio
                -- Skip grow-direction conversion when the frame has no dimensions yet
                -- (not laid out): CENTER avoids wrong edge placement from zero-size math; the bar is re-positioned after LayoutBar runs.
                if growDir and growDir ~= "CENTER" and fw >= 1 and fh >= 1 then
                    if growDir == "RIGHT" then
                        anchor = "LEFT"
                        adjX = cx - fw / 2
                        adjY = cy
                    elseif growDir == "LEFT" then
                        anchor = "RIGHT"
                        adjX = cx + fw / 2
                        adjY = cy
                    elseif growDir == "DOWN" then
                        anchor = "TOP"
                        adjY = cy + fh / 2
                        adjX = cx
                    elseif growDir == "UP" then
                        anchor = "BOTTOM"
                        adjY = cy - fh / 2
                        adjX = cx
                    end
                end
            end
        end

        -- Registered extra offset (CDM Additional Bar Offset): this centralized pass
        -- overrides the module's own placement, so it folds the same render-only
        -- displacement the anchor path folds, PRE-snap. Absent getter = 0,0; the CDM
        -- getter itself returns 0,0 while unlock mode is active.
        do
            local ex, ey = ExtraAnchorOffset(barId)
            adjX, adjY = adjX + ex, adjY + ey
        end

        -- Snap the final position to the physical pixel grid, allowing for odd-dimension
        -- frames that need half-pixel centering. adjX/adjY and the dims are UIParent
        -- units, so snap against UIParent's grid, not the frame's own.
        local PPap = CludesUI and CludesUI.PP
        if PPap and PPap.SnapCenterForDim then
            local es = uiS
            if anchor == "CENTER" then
                adjX = PPap.SnapCenterForDim(adjX, (widget:GetWidth() or 0) * fRatio, es)
                adjY = PPap.SnapCenterForDim(adjY, (widget:GetHeight() or 0) * fRatio, es)
            elseif PPap.SnapForES then
                adjX = PPap.SnapForES(adjX, es)
                adjY = PPap.SnapForES(adjY, es)
            end
        end

        -- Back into the frame's own space for SetPoint (no-op at fRatio == 1).
        if fRatio ~= 1 then
            adjX = adjX / fRatio
            adjY = adjY / fRatio
        end

        pcall(function()
            if InCombatLockdown() and widget:IsProtected() then
                -- Keyed by frame so repeated calls overwrite instead of stacking
                CludesUI._UnlockCombatQueue.Defer(widget, function()
                    pcall(function()
                        CludesUI.ClearFramePoints(widget)
                        CludesUI.SetFramePoint(widget, anchor, UIParent, "CENTER", adjX, adjY)
                    end)
                end)
                return
            end
            CludesUI.ClearFramePoints(widget)
            CludesUI.SetFramePoint(widget, anchor, UIParent, "CENTER", adjX, adjY)
        end)
        return true
    end

    -- Expose on CludesUI for child addons
    CludesUI.ConvertToCenterPos = ConvertToCenterPos
    CludesUI.ApplyCenterPosition = LM.ApplyCenterPosition

    LM.SaveBarPosition = function(barId, anchorPoint, relPoint, posX, posY)
        -- Convert to CENTER/CENTER before storing. ConvertToCenterPos reads the live
        -- frame's edges: for odd-pixel-height frames the center is integer+0.5 (e.g.
        -- 540.5), DELIBERATELY not snapped away -- the apply path uses raw fh/2 (also .5
        -- for odd heights) so cy +/- fh/2 round-trips to integer pixels; snapping here would drift 1px on save & exit.
        local cp, crp, cx, cy = ConvertToCenterPos(barId, anchorPoint, relPoint, posX, posY)

        -- Registered element?
        local elem = registeredElements[barId]
        if elem and elem.savePosition then
            -- Also hand over the PRE-conversion anchor point: when it wasn't already
            -- CENTER/CENTER, ConvertToCenterPos derived cx/cy from the element's LIVE
            -- bounds, and elements with a different stored-position footprint convention
            -- (the raid container's size tiers) rebase it in savePosition. Elements that ignore the extra args are unaffected.
            elem.savePosition(barId, cp, crp, cx, cy, anchorPoint, relPoint)
            return
        end
        -- Action bar fallback
        local saved = LM.GetPositionDB()
        if not saved then
            return
        end
        saved[barId] = { point = cp, relPoint = crp, x = cx, y = cy }
    end
    CludesUI.SaveBarPosition = LM.SaveBarPosition

    local function LoadBarPosition(barId)
        -- Registered element?
        local elem = registeredElements[barId]
        if elem and elem.loadPosition then
            return elem.loadPosition(barId)
        end
        -- Action bar fallback
        local saved = LM.GetPositionDB()
        if not saved or not saved[barId] then
            return nil
        end
        return saved[barId]
    end

    local function ClearBarPosition(barId)
        -- Registered element?
        local elem = registeredElements[barId]
        if elem and elem.clearPosition then
            elem.clearPosition(barId)
            return
        end
        -- Action bar fallback
        local saved = LM.GetPositionDB()
        if saved then
            saved[barId] = nil
        end
    end

    -------------------------------------------------------------------------------
    --  Bar frame resolution  (works for both action bars and registered elements)
    -------------------------------------------------------------------------------
    -- A module's getFrame builds its frame on first use. An error in one must not
    -- end the position pass for every other module (it once stopped Unit Frames
    -- finishing its login), so it is reported and read as "no frame".
    LM.SafeGetFrame = function(elem, key)
        local success, widget = xpcall(elem.getFrame, geterrorhandler(), key)
        if success then
            return widget
        end
    end

    LM.GetBarFrame = function(barId)
        -- Registered element?
        local elem = registeredElements[barId]
        if elem and elem.getFrame then
            return LM.SafeGetFrame(elem, barId)
        end
        -- Action bars (BAR_LOOKUP has frameName + fallbackFrame)
        local details = BAR_LOOKUP[barId]
        if details then
            local f = _G[details.frameName]
            if not f and details.fallbackFrame then
                f = _G[details.fallbackFrame]
            end
            return f
        end
        -- Extra bars (MicroBar, BagBar -- not in BAR_LOOKUP)
        if barId == "MicroBar" then
            return _G["MicroMenuContainer"] or _G["MicroMenu"]
        end
        if barId == "BagBar" then
            return _G["BagsBar"]
        end
        return nil
    end

    LM.GetBarLabel = function(barId)
        -- Registered element?
        local elem = registeredElements[barId]
        if elem and elem.label then
            return elem.label
        end
        local vals = mod.BAR_DROPDOWN_VALUES
        return vals and vals[barId] or barId
    end
    CludesUI.GetBarLabel = LM.GetBarLabel

    -- Re-read one already-built mover's name from its registered element. Movers are  -- cui-style: allow comment-budget
    -- cached in `movers` for the session, and CreateMover captures the label into a
    -- plain local upvalue (`label`) that RefreshAnchoredIdle -- fired on every hover
    -- and every anchor-state change -- keeps re-painting verbatim. Setting
    -- mover._label's text directly is therefore not enough: the next hover reverts
    -- it. mover:UpdateLabel() (defined at the end of CreateMover, in the same
    -- closure as `label`) reassigns that upvalue and re-runs the same paint
    -- RefreshAnchoredIdle uses, so the change survives the next hover too.
    --
    -- No-op when the mover was never built, so callers may fire it unconditionally
    -- right after RegisterUnlockElements. Returns false in that case, or true plus
    -- the text it applied -- callers can ignore both; the return exists so the
    -- refresh can be driven (and diagnosed) straight from a /dump.
    function CludesUI.RefreshUnlockElementLabel(key)
        local m = movers[key]
        if not (m and m.UpdateLabel) then
            return false
        end
        m:UpdateLabel()
        return true, LM.GetBarLabel(key)
    end

    -------------------------------------------------------------------------------
    --  Apply saved positions on login / reload
    -------------------------------------------------------------------------------
    -------------------------------------------------------------------------------
    --  Lazy migration: convert positions to CENTER/CENTER on the fly. Per-profile,
    --  no global flag: converted when first applied, then saved back in CENTER format.
    -------------------------------------------------------------------------------
    local function MigrateAndApplyPosition(barId, place, widget)
        if not place or not place.point then
            return false
        end
        if PositionHeld(barId) then
            return true
        end
        -- CENTER/CENTER: apply with grow-direction-aware positioning
        if place.point == "CENTER" and place.relPoint == "CENTER" then
            return LM.ApplyCenterPosition(barId, place)
        end
        -- Non-CENTER format (edge position from DB): apply directly. No write-back -- only
        -- Save & Exit (CommitPositions) saves, and the edge anchor is correct as stored.
        if widget then
            local px, py = place.x or 0, place.y or 0
            -- Same registered extra offset fold as ApplyCenterPosition (pre-snap).
            local ex, ey = ExtraAnchorOffset(barId)
            px, py = px + ex, py + ey
            local PPa = CludesUI and CludesUI.PP
            if PPa and PPa.SnapForES then
                local es = widget:GetEffectiveScale()
                px = PPa.SnapForES(px, es)
                py = PPa.SnapForES(py, es)
            end
            pcall(function()
                CludesUI.ClearFramePoints(widget)
                CludesUI.SetFramePoint(widget, place.point, UIParent, place.relPoint or place.point, px, py)
            end)
        end
        return true
    end

    local function ApplySavedPositions()
        CludesUI._applyingSavedPositions = true
        local inCombat = InCombatLockdown()

        -- Action bars: apply from the barPositions DB with lazy migration. Skipped in
        -- combat -- bar frames use SecureHandlerStateTemplate and are genuinely
        -- protected, so SetPoint is blocked by lockdown.
        local saved = LM.GetPositionDB()
        if saved and not inCombat then
            for barId, place in pairs(saved) do
                local bar = LM.GetBarFrame(barId)
                MigrateAndApplyPosition(barId, place, bar)
            end
        end
        -- Hook all known action bar frames for auto-propagation on resize
        for barId in pairs(BAR_LOOKUP) do
            HookFrameSizeChanged(barId)
        end
        -- Registered elements: let each addon apply its own positions first (CDM needs
        -- applyPosition to build/initialize frames), then override with the centralized
        -- grow-direction-aware positioning.
        RebuildRegisteredOrder()
        for _, key in ipairs(registeredOrder) do
            local elem = registeredElements[key]
            if elem then
                -- Chat frames manage their own position and must never be touched by the
                -- init loop: any hook or SetPoint on ChatFrame1 taints
                -- FCF_OpenTemporaryWindow's secure chain.
                if elem.noInitHook then
                -- Self-positioning element: skip applyPosition and the
                -- MigrateAndApplyPosition override entirely. HookFrameSizeChanged
                -- below STILL runs (dependents anchored here need resize/anchor
                -- propagation; chat is excluded inside it); NotifyElementResized delegates position re-apply back to elem.applyPosition.
                elseif true then
                    -- Let the addon initialize/build (CDM's BuildAllCDMBars); skip protected frames during combat to avoid ADDON_ACTION_BLOCKED
                    if elem.applyPosition then
                        local apFrame = elem.getFrame and LM.SafeGetFrame(elem, key)
                        if not inCombat or not apFrame or not apFrame:IsProtected() then
                            pcall(elem.applyPosition, key)
                        end
                    end
                    -- Skip centralized override for addon-internally-anchored elements
                    -- (e.g. Resource Bars anchored to each other via anchorTo setting)
                    local addonAnchored = elem.isAnchored and elem.isAnchored(key)
                    -- Also skip elements anchored via the unlock mode anchor system
                    local unlockAnchored = false
                    if not addonAnchored then
                        local adb = GetAnchorDB()
                        local ai = adb and adb[key]
                        if ai and ai.target then
                            unlockAnchored = true
                        end
                    end
                    if
                        CludesUI._TryOverrideAnchor
                        and CludesUI._TryOverrideAnchor(key, LM.GetBarFrame(key))
                    then
                    -- Override anchor owns this element's position while its
                    -- spec-override group is active (Resource Bars opt-in).
                    elseif not addonAnchored and not unlockAnchored and not elem.ownsPosition then
                        -- Override position with centralized grow-direction logic (an
                        -- element that places itself already did, in applyPosition)
                        local place = elem.loadPosition and elem.loadPosition(key)
                        if place then
                            local widget = LM.GetBarFrame(key)
                            if not inCombat or not widget or not widget:IsProtected() then
                                MigrateAndApplyPosition(key, place, widget)
                            end
                        end
                    end
                end -- elseif true
            end -- if elem
            -- Install OnSizeChanged hook so future resizes auto-propagate
            HookFrameSizeChanged(key)
        end

        -- Apply all width/height matches now that positions are set
        ApplyAllWidthHeightMatches()

        -- Reapply all anchor positions sorted by dependency depth.
        -- Parents must be positioned before children so children read correct bounds.
        local adb = GetAnchorDB()
        if adb then
            -- Build dependency-sorted list: elements with no anchored parent first
            local sorted = {}
            local visited = {}
            local function addWithDeps(childKey, details, depth)
                if visited[childKey] then
                    return
                end
                if depth > 20 then
                    return
                end -- circular guard
                visited[childKey] = true
                -- If our target is also anchored, process it first
                local targetInfo = adb[details.target]
                if targetInfo and targetInfo.target and not visited[details.target] then
                    addWithDeps(details.target, targetInfo, depth + 1)
                end
                sorted[#sorted + 1] = { key = childKey, info = details }
            end
            for childKey, details in pairs(adb) do
                if details.target then
                    addWithDeps(childKey, details, 0)
                end
            end

            local unresolved = {}
            for _, record in ipairs(sorted) do
                local childKey, details = record.key, record.info
                local childFrame = LM.GetBarFrame(childKey)
                local targetFrame = LM.GetBarFrame(details.target)
                -- Apply now if both frames exist and the target has bounds; else queue for
                -- retry. A missing child or target frame must never silently drop the
                -- anchor -- that left bars at their fallback CENTER/CENTER when an addon's
                -- element registration raced this apply. A stored fallback with a
                -- DEFINITIVELY absent target (nil frame, e.g. an empty global tracking bar
                -- group on this spec) applies immediately; a present-but-unlaid-out target still retries, so transient load states never trip the fallback.
                if
                    childFrame
                    and (
                        (targetFrame and targetFrame:GetLeft())
                        or (not targetFrame and details.fallback ~= nil)
                    )
                then
                    LM.ApplyAnchorPosition(childKey, details.target, details.side, true)
                else
                    unresolved[childKey] = details
                end
            end
            if next(unresolved) then
                local retries = 0
                local function RetryAnchors()
                    retries = retries + 1
                    local still = {}
                    for childKey, details in pairs(unresolved) do
                        local childFrame = LM.GetBarFrame(childKey)
                        local target = LM.GetBarFrame(details.target)
                        if
                            childFrame
                            and ((target and target:GetLeft()) or (not target and details.fallback ~= nil))
                        then
                            LM.ApplyAnchorPosition(childKey, details.target, details.side, true)
                        else
                            still[childKey] = details
                        end
                    end
                    unresolved = still
                    if next(unresolved) and retries < 20 then
                        C_Timer.After(0.1, RetryAnchors)
                    elseif next(unresolved) and InCombatLockdown() then
                        -- Combat reload: module builds are deferred to regen, so frames
                        -- may not resolve within the retry window. Park the keys for a
                        -- reapply when combat drops instead of dropping them.
                        for childKey in pairs(unresolved) do
                            CludesUI._AnchorPark.Park(childKey)
                        end
                    end
                end
                C_Timer.After(0, RetryAnchors)
            end
        end

        CludesUI._applyingSavedPositions = false
        CludesUI._abAnchorSuppressed = false

        -- Arm the pet watcher when any stored fallback needs it (one cheap scan;
        -- the watcher frame only exists for users who opted into a fallback).
        if CludesUI._EnsureFallbackWatchers then
            CludesUI._EnsureFallbackWatchers()
        end

        -- If we skipped protected frames, re-run once combat drops
        if inCombat then
            CludesUI._UnlockCombatQueue.Defer("ApplySavedPositions", ApplySavedPositions)
        end
    end

    -- Expose for profile import/switch (called from CludesUI_Profiles.lua)
    CludesUI._applySavedPositions = ApplySavedPositions

    -- Expose for unlock spec-overrides (position override removal / NIL apply)
    CludesUI._UnlockClearSavedPosition = ClearBarPosition

    -- Expose so child addons (CDM, resource bars) can re-apply matches after
    -- their bars finish populating and have correct dimensions.
    CludesUI.ApplyAllWidthHeightMatches = ApplyAllWidthHeightMatches

    -- Global check: is this unlock key anchored to another element?
    -- Any addon can call this to decide whether to skip positioning in BuildBars.
    function CludesUI.IsUnlockAnchored(unlockKey)
        local adb = GetAnchorDB()
        local ai = adb and adb[unlockKey]
        return ai and ai.target and true or false
    end

    -- Re-run an element's anchor. When the element's own state feeds the anchored
    -- position (see _anchorExtraOffset), that change must be pushed through the anchor
    -- rather than applied to the frame directly.
    function CludesUI.ReapplyUnlockAnchor(unlockKey)
        local adb = GetAnchorDB()
        local ai = adb and adb[unlockKey]
        if not (ai and ai.target) then
            return
        end
        LM.ApplyAnchorPosition(unlockKey, ai.target, ai.side, true)
    end

    -------------------------------------------------------------------------------
    --  Anchor guard: when Blizzard's Edit Mode repositions a bar we hold a custom
    --  position for, ours is re-applied so the bar never rests at the wrong spot. Use
    --  hooksecurefunc (post-hook), NEVER replace ApplySystemAnchor -- replacing it
    --  taints the bar frame, propagating to child action buttons and causing
    --  ADDON_ACTION_BLOCKED on SetShown(). The post-hook lets Blizzard's secure code
    --  run first, then repositions in a deferred timer so addon code never executes inside the secure call chain.
    -------------------------------------------------------------------------------
    local anchorGuardedBars = {} -- { [barFrame] = true }

    local function InstallAnchorGuard(bar, barId)
        if anchorGuardedBars[bar] then
            return
        end
        if not bar.ApplySystemAnchor then
            return
        end
        anchorGuardedBars[bar] = true
        hooksecurefunc(bar, "ApplySystemAnchor", function(self)
            local saved = LM.GetPositionDB()
            if saved and saved[barId] and saved[barId].point then
                -- Defer so we don't taint the secure execution context
                C_Timer.After(0, function()
                    if InCombatLockdown() then
                        -- Reapply once combat drops instead of losing the position
                        CludesUI._AnchorPark.ParkBarPos(barId)
                        return
                    end
                    -- Use centralized apply for grow-direction-aware positioning
                    if not LM.ApplyCenterPosition(barId, saved[barId]) then
                        pcall(function()
                            CludesUI.ClearFramePoints(self)
                            CludesUI.SetFramePoint(
                                self,
                                saved[barId].point,
                                UIParent,
                                saved[barId].relPoint,
                                saved[barId].x,
                                saved[barId].y
                            )
                        end)
                    end
                end)
            end
        end)
    end

    local function InstallAllAnchorGuards()
        local saved = LM.GetPositionDB()
        if not saved then
            return
        end
        for barId, _ in pairs(saved) do
            local bar = LM.GetBarFrame(barId)
            if bar then
                InstallAnchorGuard(bar, barId)
            end
        end
    end

    -- Hook into the addon's ApplyAll chain (action bars only)
    if ABAR then
        local _origApplyAll = ABAR.ApplyAll
        if _origApplyAll then
            function ABAR:ApplyAll()
                _origApplyAll(self)
                -- Install anchor guards on first ApplyAll (bars exist by now)
                InstallAllAnchorGuards()
                C_Timer.After(0.6, ApplySavedPositions)
            end
        end

        -- Install anchor guards as early as possible, right after the DB is initialized, so
        -- Blizzard's very first layout pass can't move bars we hold custom positions for.
        local _origOnInit = ABAR.OnInitialize
        if _origOnInit then
            function ABAR:OnInitialize()
                _origOnInit(self)
                InstallAllAnchorGuards()
                ApplySavedPositions()
            end
        end
    end

    -- Zone transition guard: suppress width/height match propagation during loading
    -- screens. CDM icon counts fluctuate as Blizzard recycles viewer frames, and transient sizes would corrupt matched elements.
    do
        local ztFrame = CreateFrame("Frame")
        ztFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        ztFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
        ztFrame:SetScript("OnEvent", function(_, evt)
            if evt == "PLAYER_LEAVING_WORLD" then
                CludesUI._zoneTransitionActive = true
            elseif evt == "PLAYER_ENTERING_WORLD" then
                -- Hold the guard 2s after zone-in so CDM/ERB finish rebuilding
                -- with final icon counts.
                C_Timer.After(2, function()
                    CludesUI._zoneTransitionActive = false
                end)
            end
        end)
    end

    -- PLAYER_ENTERING_WORLD listener, the fallback path when action bars is disabled
    -- (ApplySavedPositions is otherwise only hooked into EAB.ApplyAll/OnInitialize):
    -- applies saved positions + the initial anchor pass once child addons have had time
    -- to register their unlock elements. Every later correction is event-driven through
    -- the cascade (NotifyElementResized -> width-match propagation -> anchor children), NOT by retries.
    if not ABAR then
        local _posFrame = CreateFrame("Frame")
        _posFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        _posFrame:SetScript("OnEvent", function(self)
            -- Do NOT unregister: PEW also fires on every zone change (city->instance,
            -- M+ portal, phasing), keeping the listener live to re-run the sequence.
            -- 1s delay: addons call RegisterUnlockElements from OnEnable/their first PEW
            -- handler, so after 1s every element is registered with valid bounds. After
            -- this single pass all repositioning is event-driven via NotifyElementResized
            -- -> dependency-sorted ReapplyAll cascade. No safety sweep timer: a missed
            -- emission should be found and fixed, not papered over with periodic re-applies that themselves cause visible shifts.
            C_Timer.After(1, function()
                ApplySavedPositions()
                if CludesUI.ReapplyAllUnlockAnchors then
                    CludesUI.ReapplyAllUnlockAnchors()
                end
            end)
        end)
    end

    LM.ReapplyAllAnchors, LM.ConvertToCenterPos, LM.LoadBarPosition, LM.ClearBarPosition =
        ReapplyAllAnchors, ConvertToCenterPos, LoadBarPosition, ClearBarPosition
    LM.InstallAnchorGuard = InstallAnchorGuard
end
