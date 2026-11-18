if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_PreviewRaid.lua
--
--  The raid preview: the overlay container, RefreshPreview, the mouse
--  blockers, ShowPreview, HidePreview and the preview mode.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._previewInternals
-- CUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local max = math.max
local abs = math.abs
local ipairs = ipairs
local tostring = tostring
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame

local RF = mod._internals -- the table of the Raid Frames chain
local ApplyFont, LayoutGroups, MOVER_GROUPS = RF.ApplyFont, RF.LayoutGroups, RF.MOVER_GROUPS
local PixelSnap = RF.PixelSnap
local UpdateVisibility = mod.UpdateVisibility

local PvFrames, PvSettings, StartPvAuraTicker = Inner.PvFrames, Inner.PvSettings, Inner.StartPvAuraTicker
local StopPvAuraTicker, GetOrCreatePreviewFrame = Inner.StopPvAuraTicker, Inner.GetOrCreatePreviewFrame
local previewFrames, previewGroupLabels = Inner.previewFrames, Inner.previewGroupLabels
local BuildPreviewRoles, ApplyPreviewData = Inner.BuildPreviewRoles, Inner.ApplyPreviewData
local InitPreviewHealthValues = Inner.InitPreviewHealthValues
local previewHealthValues, previewPowerValues = Inner.previewHealthValues, Inner.previewPowerValues
local previewRoles, SetPreviewActive = Inner.previewRoles, Inner.SetPreviewActive
local SetPreviewContainer = Inner.SetPreviewContainer

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of the table that holds its list, which hands the value to
-- every copy: db, PP and containerFrame are the Raid Frames chain's.
local saved
RF.dbSetters[#RF.dbSetters + 1] = function(val)
    saved = val
end
local containerFrame
RF.containerFrameSetters[#RF.containerFrameSetters + 1] = function(val)
    containerFrame = val
end
local previewActive = false
Inner.previewActiveSetters[#Inner.previewActiveSetters + 1] = function(val)
    previewActive = val
end
local previewContainer
Inner.previewContainerSetters[#Inner.previewContainerSetters + 1] = function(val)
    previewContainer = val
end

-------------------------------------------------------------------------------
--  Overlay preview container
--  A black-background frame that holds the preview when in overlay mode.
--  Position is hardcoded (see RefreshPreview) -- it is NOT draggable and
--  nothing is saved to the profile.
-------------------------------------------------------------------------------
local overlayContainer = nil

-- The preview windows' look (raid and party): a CludesUI window of its own, a
-- dark panel with a 1px edge, a title band and an accent cap along the top.
-- Returns the title font string (font and text are set at each refresh, after
-- ApplyFont: a fontstring with no font set errors on SetText).
function mod.RF_StylePreviewWindow(oc)
    local backdrop = oc:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.055, 0.065, 0.075, 0.97)
    oc._bg = backdrop
    local function Edge(p1, p2, wid, hgt)
        local e = oc:CreateTexture(nil, "BORDER")
        e:SetColorTexture(1, 1, 1, 0.14)
        e:SetPoint(p1, oc, p1, 0, 0)
        e:SetPoint(p2, oc, p2, 0, 0)
        if wid then
            e:SetWidth(wid)
        else
            e:SetHeight(hgt)
        end
    end
    Edge("TOPLEFT", "BOTTOMLEFT", 1)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 1)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    local band = oc:CreateTexture(nil, "BACKGROUND", nil, 1)
    band:SetColorTexture(1, 1, 1, 0.05)
    band:SetPoint("TOPLEFT", oc, "TOPLEFT", 0, 0)
    band:SetPoint("TOPRIGHT", oc, "TOPRIGHT", 0, 0)
    band:SetHeight(26)
    local ACC = CludesUI.CLUDES_GREEN
    local cap = oc:CreateTexture(nil, "BORDER", nil, 1)
    cap:SetColorTexture(ACC.r, ACC.g, ACC.b, 1)
    cap:SetPoint("TOPLEFT", oc, "TOPLEFT", 0, 0)
    cap:SetPoint("TOPRIGHT", oc, "TOPRIGHT", 0, 0)
    cap:SetHeight(2)
    if CludesUI.RegAccent then
        CludesUI.RegAccent({ type = "solid", obj = cap, a = 1 })
    end
    local title = oc:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", oc, "TOPLEFT", 10, -8)
    oc._title = title
    return title
end

-- Where a preview window sits (not draggable, nothing saved): beside the
-- options panel, level with the top of its settings, on the right when it
-- fits on screen, else on the left, else over the sidebar's foot as a last
-- resort. Screen centre without the panel.
function mod.RF_DockPreviewWindow(oc)
    oc:ClearAllPoints()
    local scrollFrame = CludesUI._scrollFrame
    local l, region, t =
        scrollFrame and scrollFrame:GetLeft(),
        scrollFrame and scrollFrame:GetRight(),
        scrollFrame and scrollFrame:GetTop()
    if not (l and region and t) then
        oc:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end
    -- The panel has its own scale (Window Scale): its edges in UIParent units.
    local key = scrollFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local wid = oc:GetWidth() or 0
    local rightX = (region + 34) * key -- clear of the panel's right border
    local leftX = (l - 310) * key -- clear of the sidebar's left border
    if rightX + wid <= UIParent:GetWidth() then
        oc:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", rightX, t * key)
    elseif leftX - wid >= 0 then
        oc:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", leftX, t * key)
    else
        oc:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMLEFT", 0, 0)
    end
end

local function GetOrCreateOverlayContainer()
    if overlayContainer then
        return overlayContainer
    end

    local oc = CreateFrame("Frame", nil, UIParent)
    oc:SetFrameStrata("FULLSCREEN_DIALOG")
    oc:SetFrameLevel(10)
    oc:SetClampedToScreen(true)
    oc:Hide()

    mod.RF_StylePreviewWindow(oc)

    overlayContainer = oc
    mod._overlayContainer = oc
    return oc
end

local function RefreshPreview()
    if not previewActive then
        return
    end
    if not containerFrame then
        return
    end
    if mod._RebuildPvOverlay then
        mod._RebuildPvOverlay()
    end
    BuildPreviewRoles()

    local s = mod._pvOverlayProxy or saved.profile
    local groupGrowth = s.groupGrowth or "RIGHT"
    local unitGrowth = s.unitGrowth or "DOWN"
    -- The same self-heal the live layout runs, so the preview cannot render a
    -- grid where merged mode lays out a row (Blizzard's flat header has one
    -- column axis and cannot wrap into one).
    unitGrowth, groupGrowth = mod._RFEffectiveGrowth(unitGrowth, groupGrowth, s.mergeGroups)
    local bw = PixelSnap(s.frameWidth or 72)
    local bh = PixelSnap(s.frameHeight or 46)
    local cs = mod.RF_CellSpacing(s)
    local gs = mod.RF_GroupSpacing(s)

    -- Group bounding box
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = 5 * bw + 4 * cs
        groupH = bh
    else
        groupW = bw
        groupH = 5 * bh + 4 * cs
    end

    -- Group slot origins along the growth flow (plain direction = one run,
    -- grid flow = ns._RF_GRID_ROWS per column), same helper the live layout
    -- places real groups through.
    local gSlots, minGX, maxGY = mod._RFGroupFlow(groupGrowth, groupW, groupH, gs, 4)

    -- Unit step within a group
    local uStepX, uStepY = 0, 0
    if unitGrowth == "DOWN" then
        uStepY = -(bh + cs)
    elseif unitGrowth == "UP" then
        uStepY = (bh + cs)
    elseif unitGrowth == "RIGHT" then
        uStepX = (bw + cs)
    else -- LEFT
        uStepX = -(bw + cs)
    end

    -- Normalize unit positions within a group (0-indexed)
    local rawUX, rawUY = {}, {}
    local minUX, maxUY = 0, 0
    for index = 0, 4 do
        rawUX[index] = index * uStepX
        rawUY[index] = index * uStepY
        if rawUX[index] < minUX then
            minUX = rawUX[index]
        end
        if rawUY[index] > maxUY then
            maxUY = rawUY[index]
        end
    end

    -- Overlay mode: anchor to overlay container with padding
    local isOverlay = (saved.profile.previewMode == "overlay") or mod._testMode
    local anchor = previewContainer or containerFrame
    local anchorPad = 0
    local topExtra = 0 -- extra top space (overlay only): 25px gap above the
    -- group numbers, leaving room for the centered title
    if isOverlay then
        local oc = GetOrCreateOverlayContainer()
        anchor = oc
        anchorPad = 20
        topExtra = 25
    end

    -- Container size, through the SAME ns._RFFootprint the live container is
    -- sized with. The old one-row formula drew a 4x1 box around the grid flow's
    -- 2x2 block.
    local totalW, totalH = mod._RFFootprint(bw, bh, unitGrowth, groupGrowth, cs, gs)

    -- Pets (Show Pets on the Raid tab) go before the first or after the last group. The overlay
    -- grows to hold them; at the real position the groups stay put and the pets hang off them.
    local petSpec = mod.PF_PreviewSpec(false, s, bw, bh, cs, groupW, groupH)
    local petX, petY, padL, padT, padR, padB = 0, 0, 0, 0, 0, 0
    if petSpec then
        local slot = petSpec.before and 0 or (MOVER_GROUPS - 1)
        petX = gSlots[slot][1] - minGX + petSpec.ox
        petY = gSlots[slot][2] - maxGY + petSpec.oy
        if isOverlay then
            padL = max(0, -petX)
            padT = max(0, petY)
            padR = max(0, petX + petSpec.bw - totalW)
            padB = max(0, petSpec.bh - petY - totalH)
        end
    end

    -- Hide all preview frames first
    for _, frame in ipairs(previewFrames) do
        frame:Hide()
    end

    -- The 20-player preview keeps subgroup identities while moving each
    -- group's five frames to its visual slot.
    local groupOrder = s.customGroupOrder and not s.mergeGroups and mod._RFValidatedGroupOrder(s.groupOrder)
    local previewSlotByGroup
    if groupOrder then
        previewSlotByGroup = {}
        local previewSlot = 0
        for _, set in ipairs(groupOrder) do
            if set <= 4 then
                previewSlotByGroup[set] = previewSlot
                previewSlot = previewSlot + 1
            end
        end
    end

    -- Place 20 preview frames: 4 groups x 5 units
    local frameIdx = 0
    for g = 0, 3 do
        local displaySlot = previewSlotByGroup and previewSlotByGroup[g + 1] or g
        local gx = gSlots[displaySlot][1] - minGX
        local gy = gSlots[displaySlot][2] - maxGY
        local firstFrame -- the group's u == 0 frame, the group-number anchor
        for u = 0, 4 do
            frameIdx = frameIdx + 1
            local frame = GetOrCreatePreviewFrame(frameIdx)
            frame:ClearAllPoints()
            local fx = gx + (rawUX[u] - minUX)
            local fy = gy + (rawUY[u] - maxUY)
            frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", fx + anchorPad + padL, fy - anchorPad - topExtra - padT)
            ApplyPreviewData(frame, frameIdx)

            if frame._health and previewHealthValues[frameIdx] then
                local barPct = mod.RF_IsInvertedFill(s) and (100 - previewHealthValues[frameIdx])
                    or previewHealthValues[frameIdx]
                frame._health:SetValue(barPct)
                frame._healthPct = previewHealthValues[frameIdx]
            end
            if frame._power and previewPowerValues[frameIdx] then
                frame._power:SetValue(previewPowerValues[frameIdx])
                frame._powerPct = previewPowerValues[frameIdx]
            end
            if u == 0 then
                firstFrame = frame
            end
        end

        -- Group number label anchored to the first unit of each group
        local labelFS = previewGroupLabels[g + 1]
        if not labelFS then
            labelFS = anchor:CreateFontString(nil, "OVERLAY")
            previewGroupLabels[g + 1] = labelFS
        end
        ApplyFont(labelFS, s.groupNumberSize or 10)
        do
            -- Shared size/color with the real frames (group-number settings).
            -- Not gated by showGroupNumbers: the preview always shows numbers.
            local gc = s.groupNumberColor or {}
            labelFS:SetTextColor(gc.r or 1, gc.g or 1, gc.b or 1, gc.a or 0.75)
        end
        labelFS:SetText(tostring(g + 1))
        labelFS:ClearAllPoints()
        -- Anchor based on unit growth: label goes "before" the first unit.
        -- The X/Y offset (shared group-number setting) shifts it from there.
        local gnox = s.groupNumberOffsetX or 0
        local gnoy = s.groupNumberOffsetY or 0
        if unitGrowth == "DOWN" then
            labelFS:SetPoint("BOTTOM", firstFrame, "TOP", gnox, 4 + gnoy)
        elseif unitGrowth == "UP" then
            labelFS:SetPoint("TOP", firstFrame, "BOTTOM", gnox, -4 + gnoy)
        elseif unitGrowth == "RIGHT" then
            labelFS:SetPoint("RIGHT", firstFrame, "LEFT", -3 + gnox, gnoy)
        else -- LEFT
            labelFS:SetPoint("LEFT", firstFrame, "RIGHT", 3 + gnox, gnoy)
        end
        labelFS:Show()
    end

    -- Reparent after all frames are created (first load creates them in the loop above)
    local reparentTo = isOverlay and overlayContainer or (previewContainer or containerFrame)
    for _, frame in ipairs(previewFrames) do
        frame:SetParent(reparentTo)
    end
    -- Group-number labels go on a high-level overlay child of the same container
    -- so they draw ABOVE the preview bars (which are descendants of reparentTo);
    -- parenting them straight to reparentTo leaves them beneath the bars.
    if not mod._previewGroupNumberOverlay then
        mod._previewGroupNumberOverlay = CreateFrame("Frame", nil, reparentTo)
    end
    mod._previewGroupNumberOverlay:SetParent(reparentTo)
    mod._previewGroupNumberOverlay:SetAllPoints(reparentTo)
    mod._previewGroupNumberOverlay:SetFrameLevel(9000)
    mod._previewGroupNumberOverlay:Show()
    for _, labelFS in ipairs(previewGroupLabels) do
        labelFS:SetParent(mod._previewGroupNumberOverlay)
    end
    if petSpec then
        mod.PF_ShowPreview(
            petSpec,
            s,
            reparentTo,
            anchor,
            petX + anchorPad + padL,
            petY - anchorPad - topExtra - padT
        )
    else
        mod.PF_HidePreview()
    end

    local snapW = PixelSnap(max(totalW, 1))
    local snapH = PixelSnap(max(totalH, 1))
    if previewContainer then
        previewContainer:SetSize(snapW, snapH)
        -- Re-anchor from the saved position on EVERY refresh (mirrors the real
        -- container and the size preview; preserving a stale TOPLEFT here left the
        -- real-mode preview stranded after a growth change until the panel reopened).
        -- Anchored at the base footprint's top-left so size changes grow down/right
        -- exactly like the real container's _ApplyTierOffset scheme.
        local se = mod._PvSessionElem and mod._PvSessionElem("RF_RaidFrames")
        local bl, bt = mod._RFBaseTopLeft()
        previewContainer:ClearAllPoints()
        if se and se.point then
            -- Editing an override with a custom unlock mode: place the
            -- preview at the LAYER's recorded container position.
            previewContainer:SetPoint(
                se.point,
                UIParent,
                se.relPoint or se.point,
                PixelSnap(se.x or 0),
                PixelSnap(se.y or 0)
            )
        elseif bl then
            previewContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", PixelSnap(bl), PixelSnap(bt))
        else
            previewContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        -- Snap TOPLEFT to pixel grid (same fix as containerFrame in LayoutGroups)
        local l = previewContainer:GetLeft()
        local t = previewContainer:GetTop()
        if l and t then
            local snappedL = PixelSnap(l)
            local snappedT = PixelSnap(t)
            if abs(l - snappedL) > 0.01 or abs(t - snappedT) > 0.01 then
                previewContainer:ClearAllPoints()
                previewContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", snappedL, snappedT)
            end
        end
    end

    -- Size and position overlay container
    if isOverlay and overlayContainer then
        overlayContainer:SetSize(
            totalW + padL + padR + anchorPad * 2,
            totalH + padT + padB + anchorPad * 2 + topExtra
        )
        if overlayContainer._title then
            ApplyFont(overlayContainer._title, 13)
            overlayContainer._title:SetText(CludesUI.L("Raid Preview"):upper())
            overlayContainer._title:SetTextColor(1, 1, 1, 0.9)
            overlayContainer._title:Show()
        end
        if mod._testMode then
            -- Test mode: center on screen, above dimmer
            overlayContainer:SetFrameStrata("FULLSCREEN_DIALOG")
            overlayContainer:SetFrameLevel(55)
            overlayContainer:ClearAllPoints()
            overlayContainer:SetPoint("CENTER", UIParent, "CENTER", 80, 0)
        else
            overlayContainer:SetFrameStrata("FULLSCREEN_DIALOG")
            overlayContainer:SetFrameLevel(10)
            mod.RF_DockPreviewWindow(overlayContainer)
        end
        overlayContainer:Show()
    end
    mod.RF_PreviewCompact(previewFrames, s, false, unitGrowth)
end

-- Mouse-blocking overlays + alpha-based real-frame hide for the options preview.
-- Wrapped in a do-block, exposed via ns, so these add NO persistent main-chunk
-- locals; rfMouseBlock/partyMouseBlock survive as closure upvalues.
--
-- The overlays are OUR OWN non-secure frames, so EnableMouse is taint-free and
-- Hide() is combat-legal (no secure children) -- torn down instantly at combat
-- start, so they can never trap a healer's clicks during a pull. They track the
-- real containers directly (alpha-0 but correctly sized/positioned), covering
-- the now-invisible real unit buttons in both preview and size preview.
--
-- Real containers hide via ALPHA, not reparenting: they stay parented to
-- UIParent at their saved position, so SetAlpha(1) restore is always legal and
-- can never be deferred by combat (reparenting secure-header containers back
-- is combat-blocked -- the old cause of "no party frames for the whole first
-- pull"). Preview frames reparent to previewContainer/overlayContainer/partyOC/
-- UIParent before display, so container alpha 0 never hides the preview itself.
do
    local rfMouseBlock, partyMouseBlock
    local function setBlock(enabled)
        if enabled then
            if containerFrame then
                if not rfMouseBlock then
                    rfMouseBlock = CreateFrame("Frame", nil, UIParent)
                    rfMouseBlock:EnableMouse(true)
                end
                rfMouseBlock:SetAllPoints(containerFrame)
                rfMouseBlock:SetFrameStrata(containerFrame:GetFrameStrata())
                rfMouseBlock:SetFrameLevel(containerFrame:GetFrameLevel() + 50)
                rfMouseBlock:Show()
            end
            if mod._partyContainerFrame then
                if not partyMouseBlock then
                    partyMouseBlock = CreateFrame("Frame", nil, UIParent)
                    partyMouseBlock:EnableMouse(true)
                end
                partyMouseBlock:SetAllPoints(mod._partyContainerFrame)
                partyMouseBlock:SetFrameStrata(mod._partyContainerFrame:GetFrameStrata())
                partyMouseBlock:SetFrameLevel(mod._partyContainerFrame:GetFrameLevel() + 50)
                partyMouseBlock:Show()
            end
        else
            if rfMouseBlock then
                rfMouseBlock:Hide()
            end
            if partyMouseBlock then
                partyMouseBlock:Hide()
            end
        end
        -- The pet frames' own (their header, and the pets beside the party frames), and the
        -- party target frames' (outside the party container too).
        mod._PF_SetPreviewBlock(enabled)
        mod._PT_SetPreviewBlock(enabled)
    end
    mod._SetPreviewMouseBlock = setBlock
    mod._RefreshPreviewMouseBlockStrata = function()
        if rfMouseBlock and rfMouseBlock:IsShown() and containerFrame then
            rfMouseBlock:SetFrameStrata(containerFrame:GetFrameStrata())
            rfMouseBlock:SetFrameLevel(containerFrame:GetFrameLevel() + 50)
        end
        if partyMouseBlock and partyMouseBlock:IsShown() and mod._partyContainerFrame then
            partyMouseBlock:SetFrameStrata(mod._partyContainerFrame:GetFrameStrata())
            partyMouseBlock:SetFrameLevel(mod._partyContainerFrame:GetFrameLevel() + 50)
        end
        mod._PF_RefreshPreviewBlock()
        mod._PT_RefreshPreviewBlock()
    end
    function mod._SetRealFramesPreviewHidden(enabled)
        -- Overlay preview is a separate docked panel, so the real frames are NOT
        -- under it: leave them faintly visible (alpha 0.2) and DON'T mouse-block
        -- them. Real preview replaces the frames in place, so keep the original
        -- behavior there: hide fully (alpha 0) + block clicks.
        local isOverlay = (saved.profile.previewMode == "overlay") or mod._testMode
        if isOverlay then
            local a = enabled and 0.2 or 1
            if containerFrame then
                containerFrame:SetAlpha(a)
            end
            if mod._partyContainerFrame then
                mod._partyContainerFrame:SetAlpha(a)
            end
            if mod._ptModelOn then
                mod.RF_PtContainerAlpha(a)
            end
            if mod._PF.container then
                mod._PF.container:SetAlpha(a)
            end
            setBlock(false)
        else
            local a = enabled and 0 or 1
            if containerFrame then
                containerFrame:SetAlpha(a)
            end
            if mod._partyContainerFrame then
                mod._partyContainerFrame:SetAlpha(a)
            end
            if mod._ptModelOn then
                mod.RF_PtContainerAlpha(a)
            end
            if mod._PF.container then
                mod._PF.container:SetAlpha(a)
            end
            setBlock(enabled)
        end
        -- The pets beside the party frames take the container's alpha through their own.
        mod._PF_AlphaSync()
    end
end

local function ShowPreview()
    -- Never engage the preview unless the options window is actually open (or test mode
    -- is active). A deferred C_Timer ShowPreview firing after the panel closed (combat
    -- auto-close, rapid close) would reparent the real containers under the hidden
    -- preview parent with nothing left to restore them -- the root cause of "frames
    -- vanish after closing options". Reparenting secure-header containers is also
    -- blocked/taint-prone in combat, so bail there too.
    if not mod._testMode and not (CludesUI:IsShown()) then
        return
    end
    if InCombatLockdown() then
        return
    end
    -- Kill any active size preview
    if mod._sizePreviewTier then
        mod._sizePreviewTier = nil
        if mod._HideSizePreview then
            mod._HideSizePreview()
        end
    end
    if previewActive then
        RefreshPreview()
        return
    end
    if not containerFrame then
        return
    end
    SetPreviewActive(true)

    -- Preview container
    if not previewContainer then
        SetPreviewContainer(CreateFrame("Frame", nil, UIParent))
        previewContainer:SetFrameStrata("HIGH")
    end
    local place = saved.profile.unlockPos
    previewContainer:ClearAllPoints()
    if place then
        previewContainer:SetPoint(place.point, UIParent, place.relPoint, place.x, place.y)
    else
        previewContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    previewContainer:SetSize(containerFrame:GetSize())
    previewContainer:Show()

    -- Hide the real containers for preview via alpha (combat-reversible) instead
    -- of reparenting. SetAlpha is not protected, so the restore can never be
    -- blocked or deferred by combat. The containers stay parented to UIParent at
    -- their saved position; preview frames are reparented out of the containers
    -- by RefreshPreview below, so container alpha 0 does not hide the preview.
    mod._SetRealFramesPreviewHidden(true)

    -- Initialize health values and role assignments
    InitPreviewHealthValues()
    BuildPreviewRoles()

    RefreshPreview()
    StartPvAuraTicker()
end

-- skipRestore: leave the real frames parented to the hidden frame instead of
-- restoring them. Used on tab swaps into the party tab, where ShowPartyPreview
-- re-hides them on the next frame -- restoring here would flash the real frames
-- for one frame first. Panel close restores explicitly.
local function HidePreview(skipRestore)
    if not previewActive then
        return
    end
    mod.RF_PreviewCompact(nil, nil, false)
    SetPreviewActive(false)
    mod._previewInitialized = false
    previewRoles._randomized = nil -- re-randomize on next preview open
    previewRoles._hpalPick = nil -- re-roll the hpal Legends next open
    StopPvAuraTicker()
    mod.StopPvBuffTicker()
    -- Hide overlay container
    if overlayContainer then
        overlayContainer:Hide()
    end
    -- Hide preview container
    if previewContainer then
        previewContainer:Hide()
    end
    -- Reparent preview frames back to containerFrame
    for _, frame in ipairs(previewFrames) do
        frame:SetParent(containerFrame)
        frame:Hide()
    end
    for _, labelFS in ipairs(previewGroupLabels) do
        labelFS:SetParent(containerFrame)
        labelFS:Hide()
    end
    mod.PF_HidePreview()
    if skipRestore then
        return
    end
    -- The containers were only alpha-hidden (never reparented or moved), so the
    -- restore is a combat-legal SetAlpha(1) plus dropping the mouse blockers. No
    -- combat gate, no SetParent/SetPoint, no ns._restorePending deferral.
    mod._SetRealFramesPreviewHidden(false)
    -- Re-run layout out of combat in case frame sizes changed while previewing
    -- (LayoutGroups SetPoints secure headers, so out of combat only).
    if not InCombatLockdown() then
        LayoutGroups()
    end
    -- Re-derive the growth-corner anchor after the relayout (self-gates on
    -- combat) so a size change made while previewing can never strand the
    -- container at a stale position.
    if mod._ApplyTierOffset then
        mod._ApplyTierOffset()
    end
    UpdateVisibility()
    if mod._UpdatePartyVisibility then
        mod._UpdatePartyVisibility()
    end
end

local function ApplyPreviewMode()
    local mode = saved.profile.previewMode or "overlay"

    if mode == "none" then
        if previewActive then
            HidePreview()
        end
        return
    end
    if not previewActive then
        ShowPreview()
        return
    end
    local isOverlay = (mode == "overlay")
    if not isOverlay and overlayContainer then
        overlayContainer:Hide()
    end
    -- Re-apply the real-frame hide state for the (possibly just-changed) mode so a
    -- live Real<->Overlay switch updates alpha + mouse-block: overlay shows the
    -- real frames faintly with NO block; real hides them fully + blocks.
    mod._SetRealFramesPreviewHidden(true)
    -- RefreshPreview handles reparenting, anchoring, and overlay sizing
    RefreshPreview()
end

mod.ApplyPreviewMode = ApplyPreviewMode

-- Expose for options panel
mod.ShowPreview = ShowPreview
mod.HidePreview = HidePreview
mod.previewActive = function()
    return previewActive
end
mod.ResetPreviewRandomization = function()
    previewRoles._randomized = nil
    previewRoles._hpalPick = nil
end
mod.previewFrames = previewFrames
mod.previewHealthValues = previewHealthValues
mod.previewPowerValues = previewPowerValues

-- Party-aware sibling of PvEffectiveProfile, for the shared options tickers:
-- party preview reads party-prefixed settings, raid preview reads the live
-- profile through the real-preview effective overlay.
mod.PvSettings = PvSettings

-- Active-preview accessors for the options eyeballs (resolve raid vs party at
-- call time so the health/power animations drive whichever preview is on screen).
mod.PvActiveFrames = PvFrames
mod.PvHealthValues = function()
    return (mod._partyPvActive and mod._partyPvHV) or previewHealthValues
end
mod.PvPowerValues = function()
    return (mod._partyPvActive and mod._partyPvPV) or previewPowerValues
end
-- Re-render whichever preview is active (mirrors ShowPreview's refresh-if-active).
-- Uses the ns.* exports because ShowPartyPreview lives in CUI_RaidFrames_PreviewParty.lua.
mod.PvRefresh = function()
    if mod._partyPvActive then
        if mod.ShowPartyPreview then
            mod.ShowPartyPreview()
        end
    elseif mod.ShowPreview then
        mod.ShowPreview()
    end
end

Inner.HidePreview = HidePreview
Inner.broken = false
