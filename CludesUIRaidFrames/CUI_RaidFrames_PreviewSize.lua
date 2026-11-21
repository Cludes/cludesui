if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_RaidFrames_PreviewSize.lua
--
--  The size preview: health and power bars at a raid-size tier's
--  dimensions.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._previewInternals
-- CUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local max = math.max
local ipairs = ipairs
local tostring = tostring
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame

local RF = mod._internals -- the table of the Raid Frames chain
local MOVER_GROUPS, PixelSnap = RF.MOVER_GROUPS, RF.PixelSnap

local HidePreview = Inner.HidePreview

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of the table that holds its list, which hands the value to
-- every copy: db, PP and containerFrame are the Raid Frames chain's.
local saved
RF.dbSetters[#RF.dbSetters + 1] = function(val) saved = val end
local Pix
RF.PPSetters[#RF.PPSetters + 1] = function(val) Pix = val end
local containerFrame
RF.containerFrameSetters[#RF.containerFrameSetters + 1] = function(val) containerFrame = val end
local previewActive = false
Inner.previewActiveSetters[#Inner.previewActiveSetters + 1] = function(val) previewActive = val end

-------------------------------------------------------------------------------
--  Size preview (simple: just health + power bars at the tier's dimensions)
--  Shows the correct number of frames for the tier (10/15/25/30/40).
--  Always screen-anchored exactly where the live frames land (shared
--  growth-corner origin ns._RFTierTopLeft), regardless of preview mode.
--  No indicators, no randomization.
-------------------------------------------------------------------------------
mod._sizePreviewTier = nil
mod._sizePreviewFrames = {}
mod._sizePreviewContainer = nil

mod._ShowSizePreview = function(tier)
    -- Preview only ever runs out of combat. A mid-combat alpha-0 here could not
    -- be undone by the PLAYER_REGEN_DISABLED safety net (it already fired at
    -- combat start), and would strand the real frames invisible for the rest of
    -- the pull -- the same game-breaking outcome the alpha rework prevents.
    if InCombatLockdown() then return end
    local cfg = saved.profile
    local overrides = cfg.raidSizeOverrides
    if not overrides or not overrides[tier] then return end

    -- Hide any active previews (both real and overlay mode)
    if previewActive then
        HidePreview() -- cleans up real-mode preview frames
    end
    if mod._partyPvActive then mod.HidePartyPreview() end
    -- Hide real raid + party frames during size preview via alpha so a combat
    -- start can re-show them (Hide/Show are protected and cannot be undone in
    -- combat; SetAlpha is not). The size-preview frames live in their own
    -- UIParent child (ns._sizePreviewContainer), so container alpha does not
    -- affect them. The mouse blocker keeps the now-invisible real unit buttons
    -- from catching clicks while configuring out of combat.
    if containerFrame then containerFrame:SetAlpha(0) end
    if mod._partyContainerFrame then mod._partyContainerFrame:SetAlpha(0) end
    if mod._ptModelOn then mod.RF_PtContainerAlpha(0) end
    if mod._PF.container then mod._PF.container:SetAlpha(0) end
    mod._PF_AlphaSync()
    mod._SetPreviewMouseBlock(true)

    local shade = overrides[tier]
    local bw = PixelSnap(shade.width or cfg.frameWidth or 125)
    local bh = PixelSnap(shade.height or cfg.frameHeight or 60)
    local cs = mod.RF_CellSpacing(cfg)
    local gs = mod.RF_GroupSpacing(cfg)
    local unitGrowth, groupGrowth = mod._RFEffectiveGrowth(
        shade.unitGrowth or cfg.unitGrowth or "DOWN",
        shade.groupGrowth or cfg.groupGrowth or "RIGHT",
        cfg.mergeGroups
    )
    local frameCount = tier
    local perGroup = 5
    local numGroups = math.ceil(frameCount / perGroup)

    -- Group bounding box (same logic as LayoutGroups)
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = perGroup * bw + (perGroup - 1) * cs
        groupH = bh
    else
        groupW = bw
        groupH = perGroup * bh + (perGroup - 1) * cs
    end

    -- Unit step within a group along unitGrowth axis
    local uStepX, uStepY = 0, 0
    if unitGrowth == "DOWN" then
        uStepY = -(bh + cs)
    elseif unitGrowth == "UP" then
        uStepY = (bh + cs)
    elseif unitGrowth == "RIGHT" then
        uStepX = (bw + cs)
    else
        uStepX = -(bw + cs)
    end

    -- Normalize unit positions within a group (matches RefreshPreview pattern)
    local minUX, maxUY = 0, 0
    for u = 0, perGroup - 1 do
        local px = u * uStepX
        local py = u * uStepY
        if px < minUX then minUX = px end
        if py > maxUY then maxUY = py end
    end

    -- Total bounding box: the tier's group mover footprint via the SAME
    -- ns._RFFootprint the live container sizing and the corner origin use (one
    -- formula, so preview and live can never drift).
    local totalW, totalH = mod._RFFootprint(bw, bh, unitGrowth, groupGrowth, cs, gs)

    -- Tier offset
    local tierOX = shade.offsetX or 0
    local tierOY = shade.offsetY or 0

    -- Create or reuse container
    local boxHolder = mod._sizePreviewContainer
    if not boxHolder then
        boxHolder = CreateFrame("Frame", nil, UIParent)
        boxHolder:SetFrameStrata("FULLSCREEN_DIALOG")
        boxHolder:SetFrameLevel(10)
        -- Never clamp: the preview must land exactly where the live
        -- container lands, including partially off-screen positions.
        boxHolder:SetClampedToScreen(false)
        mod._sizePreviewContainer = boxHolder
    end

    -- Always use real positioning (where frames actually sit)
    local pad = 0
    boxHolder:SetSize(totalW, totalH)
    if boxHolder._bg then boxHolder._bg:Hide() end
    boxHolder:SetFrameStrata("HIGH")
    boxHolder:ClearAllPoints()
    -- Same growth-corner origin as the live container (_ApplyTierOffset):
    -- the tier footprint's growth-derived corner pins at the base
    -- footprint's same corner plus the tier offset, via the shared
    -- ns._RFTierTopLeft -- the preview lands exactly where live lands.
    local centered = mod._RFGroupCentered(shade, groupGrowth)
    local px, py = mod._RFTierTopLeft(totalW, totalH, unitGrowth, groupGrowth, tierOX, tierOY, centered)
    if px then
        boxHolder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", PixelSnap(px), PixelSnap(py))
    else
        boxHolder:SetPoint("CENTER", UIParent, "CENTER", tierOX, tierOY)
    end

    -- Font for the unit-number label
    local fontFile = (CUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    local nameSize = cfg.nameSize or 10

    -- Group slot origins along the growth flow, normalized over MOVER_GROUPS
    -- (matching the real LayoutGroups container). At least MOVER_GROUPS slots
    -- are generated even when the tier shows fewer groups: the normalization
    -- origin is what puts slot 0 at the growth corner, so normalizing over a
    -- 2- or 3-group prefix would place the preview on the wrong side of the
    -- box for LEFT/UP growth. The extra slots are simply not drawn.
    local gSlots, minX, maxY = mod._RFGroupFlow(groupGrowth, groupW, groupH, gs, max(numGroups, MOVER_GROUPS))
    -- Center Groups: the tier's full group count centered in the box, as live
    -- (which centers up to the last group holding members, in both modes).
    local shiftX, shiftY = 0, 0
    if centered then
        shiftX, shiftY = mod._RFCenterShift(gSlots, numGroups)
    end

    local groupOrder = cfg.customGroupOrder
        and not cfg.mergeGroups
        and mod._RFValidatedGroupOrder(cfg.groupOrder)
    local sizePreviewSlotByGroup
    if groupOrder then
        sizePreviewSlotByGroup = {}
        local sizePreviewSlot = 0
        for _, set in ipairs(groupOrder) do
            if set <= numGroups then
                sizePreviewSlotByGroup[set] = sizePreviewSlot
                sizePreviewSlot = sizePreviewSlot + 1
            end
        end
    end

    for index = 1, frameCount do
        local frame = mod._sizePreviewFrames[index]
        if not frame then
            frame = CreateFrame("Frame", nil, boxHolder)
            local health = CreateFrame("StatusBar", nil, frame)
            health:SetPoint("TOPLEFT")
            health:SetPoint("TOPRIGHT")
            health:SetMinMaxValues(0, 100)
            health:SetValue(100)
            -- Pre-paint tint (see StyleButton's health bar note).
            health:SetStatusBarColor(0.12, 0.12, 0.12)
            if Pix then Pix.DisablePixelSnap(health) end
            frame._health = health

            local backdrop = frame:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            if Pix then Pix.DisablePixelSnap(backdrop) end
            frame._bg = backdrop

            local power = CreateFrame("StatusBar", nil, frame)
            power:SetPoint("BOTTOMLEFT")
            power:SetPoint("BOTTOMRIGHT")
            power:SetMinMaxValues(0, 1)
            power:SetValue(1)
            if Pix then Pix.DisablePixelSnap(power) end
            frame._power = power

            local bdr = CreateFrame("Frame", nil, frame)
            bdr:SetAllPoints()
            bdr:SetFrameLevel(frame:GetFrameLevel() + 2)
            if Pix then Pix.CreateBorder(bdr, 0, 0, 0, 1, 1) end
            frame._border = bdr

            -- Name text
            local nameFS = health:CreateFontString(nil, "OVERLAY")
            nameFS:SetJustifyH("CENTER")
            nameFS:SetWordWrap(false)
            frame._nameText = nameFS

            -- Top Name Bar
            local tnb = CreateFrame("Frame", nil, frame)
            tnb:SetFrameLevel(frame:GetFrameLevel() + 4)
            tnb:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            tnb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
            tnbBg:SetAllPoints()
            if Pix then Pix.DisablePixelSnap(tnbBg) end
            local tnbText = tnb:CreateFontString(nil, "OVERLAY")
            tnbText:SetWordWrap(false)
            tnb:Hide()
            frame._topNameBar = tnb
            frame._topNameBarBg = tnbBg
            frame._topNameBarText = tnbText

            -- Role icon
            local roleIcon = health:CreateTexture(nil, "OVERLAY")
            roleIcon:Hide()
            frame._roleIcon = roleIcon

            mod._sizePreviewFrames[index] = frame
        end

        frame:SetParent(boxHolder)
        frame:SetSize(bw, bh)
        -- GENERIC SIZING PLACEHOLDER (NOT a style preview):
        -- The custom raid-size previews (10/15/25/30) deliberately do NOT mimic the
        -- user's real raid-frame style. They render as plain blocks that only show
        -- each frame's footprint at the chosen width/height/spacing, so the size
        -- preview can never be mistaken for a live style preview when it does not
        -- match the user's customized frames. No class colors, textures, power bars,
        -- names, role icons or custom border -- just a flat fill, a thin neutral
        -- outline and the unit number.
        frame._health:ClearAllPoints()
        frame._health:SetAllPoints(frame)
        frame._health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        if frame._health:GetStatusBarTexture() then
            frame._health:GetStatusBarTexture():SetHorizTile(false)
        end
        frame._health:SetStatusBarColor(0.24, 0.26, 0.30, 1)
        frame._health:SetValue(100)
        frame._bg:SetColorTexture(0.09, 0.09, 0.11, 1)
        if frame._power then frame._power:Hide() end
        if frame._topNameBar then frame._topNameBar:Hide() end
        if frame._roleIcon then
            frame._roleIcon:Hide()
            if frame._roleIcon._roleText then frame._roleIcon._roleText:Hide() end
        end

        -- Thin neutral outline so each block and the spacing between them reads clearly.
        if frame._border and Pix then
            frame._border:SetFrameLevel(frame:GetFrameLevel() + 2)
            CUI.ApplyBorderStyle(
                frame._border,
                1,
                0.7,
                0.7,
                0.75,
                0.8,
                "solid",
                nil,
                nil,
                nil,
                nil,
                "unitframes",
                1
            )
        end

        -- Centered unit number.
        if frame._nameText then
            CUI.ApplyModuleFont(frame._nameText, fontFile, math.max(11, nameSize), "raidFrames")
            frame._nameText:SetText(tostring(index))
            frame._nameText:SetTextColor(0.9, 0.9, 0.9)
            frame._nameText:SetWidth(bw)
            frame._nameText:ClearAllPoints()
            frame._nameText:SetPoint("CENTER", frame._health, "CENTER", 0, 0)
            frame._nameText:Show()
        end

        -- Position: group index + unit index within group
        local groupIdx = math.ceil(index / perGroup) - 1
        local unitIdx = (index - 1) % perGroup

        -- Group origin (TOPLEFT-relative, adjusted for growth direction)
        local displaySlot = sizePreviewSlotByGroup and sizePreviewSlotByGroup[groupIdx + 1] or groupIdx
        local gx = gSlots[displaySlot][1] - minX + shiftX
        local gy = gSlots[displaySlot][2] - maxY + shiftY

        -- Unit offset within group (TOPLEFT-normalized, matching RefreshPreview)
        local ux = unitIdx * uStepX - minUX
        local uy = unitIdx * uStepY - maxUY

        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", boxHolder, "TOPLEFT", pad + gx + ux, -pad + gy + uy)
        frame:Show()
    end

    -- Hide excess frames
    for index = frameCount + 1, #mod._sizePreviewFrames do
        mod._sizePreviewFrames[index]:Hide()
    end

    boxHolder:Show()
end

mod._HideSizePreview = function()
    if mod._sizePreviewContainer then mod._sizePreviewContainer:Hide() end
    for _, frame in ipairs(mod._sizePreviewFrames) do
        frame:Hide()
    end
    -- Restore real frame opacity (size preview only changed alpha, never the
    -- Shown state) and drop the mouse blocker. SetAlpha(1) is always legal, in
    -- or out of combat, so the frames can never be stranded invisible.
    if containerFrame then containerFrame:SetAlpha(1) end
    if mod._partyContainerFrame then mod._partyContainerFrame:SetAlpha(1) end
    if mod._ptModelOn then mod.RF_PtContainerAlpha(1) end
    if mod._PF.container then mod._PF.container:SetAlpha(1) end
    mod._PF_AlphaSync()
    mod._SetPreviewMouseBlock(false)
    -- Recompute party visibility (only shows party frames if actually grouped /
    -- Show When Solo). Bails in combat; the alpha restore above suffices there.
    if mod._UpdatePartyVisibility then mod._UpdatePartyVisibility() end
end

Inner.broken = false
