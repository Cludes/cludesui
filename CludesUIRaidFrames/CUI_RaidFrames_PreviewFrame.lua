if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_PreviewFrame.lua
--
--  The standalone preview frames: CreatePreviewFrame and its container
--  state.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._previewInternals
-- CUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local ipairs = ipairs
local CreateFrame = CreateFrame

local RF = mod._internals -- the table of the Raid Frames chain
local ApplyFont, defaultSet, IsPowerBarEnabled = RF.ApplyFont, RF.defaults, RF.IsPowerBarEnabled
local PixelSnap, ResolveHealthTexture = RF.PixelSnap, RF.ResolveHealthTexture

local previewFrames, PvActive, PvFrames = Inner.previewFrames, Inner.PvActive, Inner.PvFrames

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of the table that holds its list, which hands the value to
-- every copy: db, PP and containerFrame are the Raid Frames chain's.
local saved
RF.dbSetters[#RF.dbSetters + 1] = function(val) saved = val end
local Pix
RF.PPSetters[#RF.PPSetters + 1] = function(val) Pix = val end
local containerFrame
RF.containerFrameSetters[#RF.containerFrameSetters + 1] = function(val) containerFrame = val end

-- Preview frames: standalone frames NOT managed by SecureGroupHeaderTemplate.
-- Header-managed buttons can't be shown without real units, so we create
-- our own lightweight frames that look identical for the options preview.
local previewGroupLabels = {} -- [1..4] FontStrings showing group numbers
local previewContainer = nil -- standalone anchor frame for preview (doesn't move with containerFrame)
Inner.previewContainerSetters[#Inner.previewContainerSetters + 1] = function(val) previewContainer = val end

local function CreatePreviewFrame(index, party)
    local cfg = saved.profile
    local wid = PixelSnap(cfg.frameWidth or 72)
    local hgt = PixelSnap(cfg.frameHeight or 46)
    local powerH = IsPowerBarEnabled(cfg) and PixelSnap(cfg.powerHeight or 4) or 0
    -- Party Frames kit (party preview only): the stock frame's own layout.
    local kit = party and mod.RF_PartyKit()
    local healthH = PixelSnap(hgt - mod.RF_HealthPowerInset(cfg, powerH))

    local frame = CreateFrame("Frame", nil, previewContainer or containerFrame)
    frame:SetSize(wid, hgt)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- Background
    local bgc = cfg.customBgColor or defaultSet.customBgColor
    local backdrop = frame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(bgc.r, bgc.g, bgc.b, (cfg.bgDarkness or 50) / 100)
    if Pix then Pix.DisablePixelSnap(backdrop) end

    -- Health bar
    local health = CreateFrame("StatusBar", nil, frame)
    health:SetFrameLevel(frame:GetFrameLevel() + 2)
    health:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    health:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    health:SetHeight(healthH)
    health:SetStatusBarTexture(ResolveHealthTexture())
    health:GetStatusBarTexture():SetHorizTile(false)
    if Pix then Pix.DisablePixelSnap(health) end
    health:SetMinMaxValues(0, 100)
    health:SetValue(100)

    -- Full-height anchor reference (mirrors the live buttons' d.uniformRef so
    -- Uniform Icon Anchoring previews identically; see ns.RF_AnchorHost).
    frame._uniformRef = CreateFrame("Frame", nil, frame)
    frame._uniformRef:SetFrameLevel(health:GetFrameLevel())
    frame._uniformRef:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    frame._uniformRef:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    health._cuiUniformRef = frame._uniformRef
    frame._uniformRef._cuiHealth = health

    -- Absorb shield preview (dual clip-frame, matching real frames)
    -- Mask: constrains absorb rendering to health bar bounds
    local absorbMask = health:CreateMaskTexture()
    absorbMask:SetAllPoints(health)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Current HP clip: bounds the backfill bar to the filled health area
    local curClip = CreateFrame("Frame", nil, health)
    curClip:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    curClip:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    curClip:SetClipsChildren(true)

    -- Missing HP clip: bounds the forward bar to the empty health area
    local missClip = CreateFrame("Frame", nil, health)
    missClip:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", -1, 0)
    missClip:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    missClip:SetClipsChildren(true)

    -- Backfill bar: grows into filled health from the right (overshield)
    local backfillBar = CreateFrame("StatusBar", nil, curClip)
    backfillBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local bfFill = backfillBar:GetStatusBarTexture()
    if bfFill then
        bfFill:SetDrawLayer("ARTWORK", 1)
        bfFill:AddMaskTexture(absorbMask)
    end
    -- Modern compound absorb base (preview): mirrors the live frame's solid c6c8ff
    -- base drawn under the striped fill. Anchored to the fill at render time.
    local bfBase = backfillBar:CreateTexture(nil, "ARTWORK", nil, 0)
    bfBase:SetColorTexture(0.776, 0.784, 1.0, 1)
    if absorbMask then bfBase:AddMaskTexture(absorbMask) end
    bfBase:Hide()
    backfillBar._modernBase = bfBase
    backfillBar:SetStatusBarColor(1, 1, 1, 0.3)
    backfillBar:SetReverseFill(true)
    backfillBar:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
    backfillBar:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    backfillBar:SetWidth(health:GetWidth())
    backfillBar:SetHeight(health:GetHeight())
    -- Absorb on top of the HP cluster (above heal absorb/heal pred and max health).
    backfillBar:SetFrameLevel(health:GetFrameLevel() + 3)
    backfillBar:SetMinMaxValues(0, 100)
    backfillBar:Hide()

    -- Forward bar: grows into missing health from the HP edge
    local forwardBar = CreateFrame("StatusBar", nil, missClip)
    forwardBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local fwFill = forwardBar:GetStatusBarTexture()
    if fwFill then
        fwFill:SetDrawLayer("ARTWORK", 1)
        fwFill:AddMaskTexture(absorbMask)
    end
    -- Modern compound absorb base (preview) for the forward bar.
    local fwBase = forwardBar:CreateTexture(nil, "ARTWORK", nil, 0)
    fwBase:SetColorTexture(0.776, 0.784, 1.0, 1)
    if absorbMask then fwBase:AddMaskTexture(absorbMask) end
    fwBase:Hide()
    forwardBar._modernBase = fwBase
    forwardBar:SetStatusBarColor(1, 1, 1, 0.3)
    forwardBar:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    forwardBar:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    forwardBar:SetWidth(health:GetWidth())
    forwardBar:SetHeight(health:GetHeight())
    -- Match backfill (the heal prediction draws over it at this level, as live).
    forwardBar:SetFrameLevel(health:GetFrameLevel() + 3)
    forwardBar:SetMinMaxValues(0, 100)
    forwardBar:Hide()

    -- "Default Blizz Frames" spark (preview): mirrors live -- a fixed 16px cast_spark
    -- glow on a non-clipping host above the shield, CENTER pinned to the forward bar's
    -- LEFT edge (the seam). Gated by the preview's plain absorb compare in the renderer.
    local sparkHost = CreateFrame("Frame", nil, health)
    sparkHost:SetAllPoints(health)
    sparkHost:SetClipsChildren(true)
    sparkHost:SetFrameLevel(health:GetFrameLevel() + 4)
    local gateBar = CreateFrame("StatusBar", nil, sparkHost)
    gateBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    gateBar:SetStatusBarColor(1, 1, 1, 0)
    gateBar:SetSize(16, health:GetHeight())
    gateBar:SetMinMaxValues(0, 1)
    gateBar:SetValue(0)
    gateBar:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    local edgeSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    edgeSpark:SetTexture("Interface\\AddOns\\CludesUI\\media\\cast_spark.tga")
    edgeSpark:SetBlendMode("ADD")
    edgeSpark:SetAllPoints(gateBar:GetStatusBarTexture())
    edgeSpark:Hide()
    forwardBar._edgeSpark = edgeSpark
    forwardBar._edgeGate = gateBar
    -- Overshield spark (preview): rides the backfill's left edge while overshielding.
    local bfSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    bfSpark:SetTexture("Interface\\AddOns\\CludesUI\\media\\cast_spark.tga")
    bfSpark:SetBlendMode("ADD")
    bfSpark:SetSize(16, health:GetHeight())
    bfSpark:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    bfSpark:Hide()
    forwardBar._bfSpark = bfSpark

    -- Heal absorb bar (preview): red overlay eating into filled health from HP edge
    do
        -- Own clip frame (mirrors live): right/left span the full bar, overlay
        -- clips to filled health. Bounds set per healAbsorbEdgeMode in render.
        local healClip = CreateFrame("Frame", nil, health)
        healClip:SetClipsChildren(true)
        healClip:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        healClip:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        frame._healClip = healClip
        local ha = CreateFrame("StatusBar", nil, healClip)
        ha:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local hf = ha:GetStatusBarTexture()
        if hf then
            hf:SetDrawLayer("ARTWORK", 2)
            hf:AddMaskTexture(absorbMask)
        end
        ha:SetStatusBarColor(0.8, 0.15, 0.15, 0.65)
        ha:SetReverseFill(true)
        ha:SetPoint("TOPRIGHT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        ha:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        ha:SetWidth(health:GetWidth())
        ha:SetHeight(health:GetHeight())
        ha:SetFrameLevel(health:GetFrameLevel() + 1)
        ha:SetMinMaxValues(0, 100)
        ha._mask = absorbMask
        -- Black backing behind the heal-absorb texture (preview; mirrors live).
        local haBg = ha:CreateTexture(nil, "ARTWORK", nil, 1)
        haBg:SetColorTexture(0, 0, 0, 0.25)
        if absorbMask then haBg:AddMaskTexture(absorbMask) end
        haBg:Hide()
        ha._bg = haBg
        ha:Hide()
        frame._healAbsorbBar = ha
    end

    -- Heal prediction bar (preview): extends from HP edge into missing health
    do
        local hp = CreateFrame("StatusBar", nil, missClip)
        hp:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local hf = hp:GetStatusBarTexture()
        if hf then
            hf:SetDrawLayer("ARTWORK", 2)
            hf:AddMaskTexture(absorbMask)
        end
        hp:SetStatusBarColor(0.3, 0.8, 0.3, 0.4)
        hp:SetReverseFill(false)
        hp:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        hp:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        hp:SetWidth(health:GetWidth())
        hp:SetHeight(health:GetHeight())
        hp:SetFrameLevel(health:GetFrameLevel() + 3) -- over the absorb, as live
        hp:SetMinMaxValues(0, 100)
        hp:Hide()
        frame._healPredBar = hp
    end

    -- Reduced max health bar (preview): black bg + red striped overlay on right side
    do
        local rmh = CreateFrame("StatusBar", nil, health)
        rmh:SetStatusBarTexture(CludesUI.MAX_HEALTH_STRIPES_TEX)
        local rmhFill = rmh:GetStatusBarTexture()
        if rmhFill then
            rmhFill:SetDrawLayer("ARTWORK", 3)
            rmhFill:SetHorizTile(true)
            rmhFill:SetVertTile(true)
        end
        rmh:SetStatusBarColor(0.7, 0.1, 0.1, 1)
        rmh:SetReverseFill(true)
        rmh:SetAllPoints(health)
        rmh:SetFrameLevel(health:GetFrameLevel() + 2)
        rmh:SetMinMaxValues(0, 1)
        rmh:Hide()
        -- Black background behind the stripes
        local rmhBg = rmh:CreateTexture(nil, "ARTWORK", nil, 2)
        rmhBg:SetAllPoints(rmhFill)
        rmhBg:SetColorTexture(0, 0, 0, 1)
        frame._reducedMaxHealthBar = rmh
        frame._reducedMaxHealthBg = rmhBg
    end

    -- Store absorb references on preview frame
    local absorbBar = backfillBar
    absorbBar._forward = forwardBar
    absorbBar._mask = absorbMask
    absorbBar._curClip = curClip
    absorbBar._missClip = missClip

    -- Absorb Bar (preview): solid bar above the frame, fills from the right
    do
        local tb = CreateFrame("StatusBar", nil, frame)
        tb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        tb:SetStatusBarColor(1, 1, 1, 1)
        tb:SetReverseFill(true)
        tb:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
        tb:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 0)
        tb:SetHeight(4)
        tb:SetFrameLevel(health:GetFrameLevel() + 3)
        tb:SetMinMaxValues(0, 100)
        tb:Hide()
        absorbBar._topBar = tb
    end

    -- Heal Absorb Bar (preview): mirrors the Absorb Bar strip above.
    do
        local thb = CreateFrame("StatusBar", nil, frame)
        thb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        thb:SetStatusBarColor(200 / 255, 29 / 255, 29 / 255, 1)
        thb:SetReverseFill(true)
        thb:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
        thb:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 0)
        thb:SetHeight(4)
        thb:SetFrameLevel(health:GetFrameLevel() + 3)
        thb:SetMinMaxValues(0, 100)
        thb:Hide()
        absorbBar._healTopBar = thb
    end

    -- Power bar (anchored to frame bottom for pixel alignment). Always built:
    -- frames are reused for the session and the party preview reads its own
    -- role flags, so ApplyPreviewData shows or hides it per unit.
    local power
    do
        power = CreateFrame("StatusBar", nil, frame)
        power:SetFrameLevel(frame:GetFrameLevel() + 3)
        power:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        power:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        power:SetHeight(powerH)
        power:SetStatusBarTexture(ResolveHealthTexture())
        power:GetStatusBarTexture():SetHorizTile(false)
        if Pix then Pix.DisablePixelSnap(power) end
        power:SetMinMaxValues(0, 100)
        power:SetValue(100)
        local pwBg = power:CreateTexture(nil, "BACKGROUND")
        pwBg:SetAllPoints()
        pwBg:SetColorTexture(
            (cfg.powerBgColor or {}).r or 0,
            (cfg.powerBgColor or {}).g or 0,
            (cfg.powerBgColor or {}).b or 0,
            (cfg.powerBgDarkness or 70) / 100
        )
        if Pix then Pix.DisablePixelSnap(pwBg) end
        frame._powerBg = pwBg

        -- Power border
        local pwBdr = CreateFrame("Frame", nil, frame)
        pwBdr:SetAllPoints(power)
        pwBdr:SetFrameLevel(power:GetFrameLevel() + 1)
        if Pix then Pix.CreateBorder(pwBdr, 0, 0, 0, 1, 1) end
        frame._powerBorder = pwBdr
    end

    -- Border (single border styled via ApplyBorderStyle in ApplyPreviewData,
    -- recolored by state -- mirrors the real frames)
    local bdrFrame = CreateFrame("Frame", nil, frame)
    bdrFrame:SetAllPoints(frame)
    bdrFrame:SetFrameLevel(frame:GetFrameLevel() + 8)

    local function PvPaintBorder()
        if not Pix then return end
        -- Overlay ahead of _scaledProfile: border/hover/target keys are not
        -- tier-scaled, so the effective overlay may shadow them safely.
        local cfg = mod._previewSettingsOverride
            or (mod._partyPvActive and mod._scaledPartyProxy)
            or mod._pvOverlayProxy
            or mod._scaledProfile
        if mod.RF_ButtonCompact(frame, cfg) then
            mod.RF_CompactHighlight(bdrFrame, frame, cfg, frame)
            return
        end
        if frame.kit then
            mod.RF_KitHighlight(
                frame,
                bdrFrame,
                cfg,
                frame._hovered and cfg.hoverBorderEnabled ~= false,
                frame._isTarget and cfg.targetBorderEnabled ~= false
            )
            return
        end
        if frame.stockEdge then
            local hover = frame._hovered and cfg.hoverBorderEnabled ~= false
            local lvl = frame:GetFrameLevel() + (hover and mod.LVL_RAISE or 8)
            if bdrFrame:GetFrameLevel() ~= lvl then
                bdrFrame:SetFrameLevel(lvl)
                local boxHolder = Pix.GetBorders(bdrFrame)
                if boxHolder then boxHolder:SetFrameLevel(lvl + 1) end
            end
            mod.RF_StockHighlight(
                frame,
                bdrFrame,
                cfg,
                hover,
                frame._isTarget and cfg.targetBorderEnabled ~= false
            )
            return
        end
        local red, green, blue, a
        local raised, hlSize, hlPx = false, nil, nil
        if frame._pvDispelBdrC and cfg.borderBehind then
            -- Show Behind: the live copy sits over the never-raised base border, so the
            -- type color covers hover/target there too.
            local color = frame._pvDispelBdrC
            red, green, blue, a = color.r, color.g, color.b, color.a or 1
        elseif frame._hovered and cfg.hoverBorderEnabled ~= false then
            local color = cfg.hoverBorderColor or { r = 1, g = 1, b = 1 }
            red, green, blue, a = color.r, color.g, color.b, cfg.hoverBorderAlpha or 1
            raised, hlSize = true, cfg.hoverBorderSize or 1
            hlPx = CludesUI.BorderPx(cfg.hoverBorderSizePx, hlSize, cfg.borderTexture or "solid")
        elseif frame._isTarget and cfg.targetBorderEnabled ~= false then
            local color = cfg.targetBorderColor or { r = 1, g = 1, b = 1 }
            red, green, blue, a = color.r, color.g, color.b, cfg.targetBorderAlpha or 1
            raised, hlSize = true, cfg.targetBorderSize or 1
            hlPx = CludesUI.BorderPx(cfg.targetBorderSizePx, hlSize, cfg.borderTexture or "solid")
        elseif frame._pvAggroBdr then
            -- Threat Borders' Color Custom Borders (set by ApplyPreviewData): the threat
            -- color, raised like the real frames, below hover/target and above dispel.
            red, green, blue, a = 1, 0, 0, 1
            raised = true
        elseif frame._pvDispelBdrC then
            -- Color Custom Borders (set by ApplyPreviewData): the type color, below hover/target.
            local color = frame._pvDispelBdrC
            red, green, blue, a = color.r, color.g, color.b, color.a or 1
        else
            local color = cfg.borderColor or { r = 0, g = 0, b = 0 }
            red, green, blue, a = color.r, color.g, color.b, cfg.borderAlpha or 1
        end
        -- Match real frames: raise the inset border above overlapping neighbors
        -- while highlighted (handles negative Frame Spacing in the preview too).
        -- Guard the level writes so a refresh only touches them on a real change.
        local pl = frame:GetFrameLevel()
        local lvl = cfg.borderBehind and math.max(0, pl - 1) or (pl + (raised and mod.LVL_RAISE or 8))
        local boxHolder = Pix.GetBorders(bdrFrame)
        if bdrFrame:GetFrameLevel() ~= lvl or (boxHolder and boxHolder:GetFrameLevel() ~= lvl + 1) then
            bdrFrame:SetFrameLevel(lvl)
            if boxHolder then boxHolder:SetFrameLevel(lvl + 1) end
            -- Textured styles: the backdrop child too, as on live frames.
            local edge = CludesUI._bdBorderData and CludesUI._bdBorderData[bdrFrame]
            if edge then edge:SetFrameLevel(lvl) end
        end
        if (cfg.borderSize or 1) <= 0 then
            mod.ApplyHighlightBorder(bdrFrame, cfg, hlSize, red, green, blue, a, hlPx)
            return
        end
        if hlSize then
            red, green, blue = mod.RF_VisibleHighlight(cfg, red, green, blue)
        end
        bdrFrame._hlBorderSize = nil
        CludesUI.SetBorderStyleColor(bdrFrame, red, green, blue, a)
        if
            cfg.powerBorderMatchColor == true
            and frame._powerBorder
            and frame._powerBorder._powerArtMode == "divider"
        then
            mod.RF_ColorPowerDivider(frame._powerBorder, red, green, blue, a)
        end
        if cfg.topNameBarDividerMatchColor == true and frame._topNameBar and frame._topNameBar._divider then
            mod.RF_ColorPowerDivider(frame._topNameBar._divider, red, green, blue, a)
        end
    end
    frame._ApplyBorderColor = PvPaintBorder

    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function()
        frame._hovered = true
        PvPaintBorder()
    end)
    frame:SetScript("OnLeave", function()
        frame._hovered = false
        PvPaintBorder()
    end)

    -- Threat border (aggro indicator)
    local threatFrame = CreateFrame("Frame", nil, frame)
    threatFrame:SetAllPoints(frame)
    threatFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
    threatFrame:Hide()
    if Pix then Pix.CreateBorder(threatFrame, 1, 0, 0, 1, 2) end

    -- Click to toggle target in test mode (recolors the single border)
    frame:SetScript("OnMouseDown", function(self)
        if not PvActive() then return end
        for _, popFrame in ipairs(PvFrames()) do
            if popFrame ~= self and popFrame._isTarget then
                popFrame._isTarget = false
                if popFrame._ApplyBorderColor then popFrame._ApplyBorderColor() end
            end
        end
        frame._isTarget = true
        PvPaintBorder()
    end)

    -- Dispel border
    local dispelBdrFrame = CreateFrame("Frame", nil, frame)
    dispelBdrFrame:SetAllPoints(health)
    dispelBdrFrame:SetFrameLevel(frame:GetFrameLevel() + mod.LVL_RAISE - 1)
    dispelBdrFrame:Hide()
    if Pix then Pix.CreateBorder(dispelBdrFrame, 0.2, 0.6, 1, 1, 2) end

    -- Dispel overlay (texture on health bar at ARTWORK sublevel 3: above fill
    -- and above the BM health-color overlay (sublevel 2), below absorbs/text)
    local dispelOLTex = health:CreateTexture(nil, "ARTWORK", nil, 3)
    dispelOLTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    dispelOLTex:Hide()

    -- Dispel type icon. Preview parity with the real frames' dispel icon
    -- band: above the aura band so it covers debuff icons sharing its
    -- corner, below the marker band.
    local dispelIconFrame = CreateFrame("Frame", nil, frame)
    dispelIconFrame:SetFrameLevel(frame:GetFrameLevel() + mod.LVL_MARKER - 1)
    dispelIconFrame:SetSize(16, 16)
    dispelIconFrame:SetPoint("CENTER", health, "CENTER", 0, 0)
    dispelIconFrame:Hide()
    local dispelIconTex = dispelIconFrame:CreateTexture(nil, "ARTWORK")
    dispelIconTex:SetAllPoints()
    dispelIconTex:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Marker carrier: above the frame border (incl. hover/target raise) so the
    -- leader icon and raid marker render on top of it (mirrors real frames).
    local markerCarrier = CreateFrame("Frame", nil, frame)
    markerCarrier:SetAllPoints(health)
    markerCarrier:SetFrameLevel(frame:GetFrameLevel() + mod.LVL_MARKER)

    -- Raid marker (on marker carrier, above the border)
    local raidMarker = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 2)
    local rmSz = PixelSnap(cfg.raidMarkerSize or 16)
    raidMarker:SetSize(rmSz, rmSz)
    raidMarker:Hide()

    -- Ready check icon (position/size re-applied in the preview indicator pass)
    local readyCheck = markerCarrier:CreateTexture(nil, "OVERLAY")
    readyCheck:SetSize(PixelSnap(cfg.readyCheckSize or 20), PixelSnap(cfg.readyCheckSize or 20))
    readyCheck:SetPoint("CENTER", health, "CENTER", 0, 0)
    readyCheck:Hide()

    -- Combat icon (position/size/style re-applied in the preview indicator pass)
    local combatIcon = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 1)
    combatIcon:SetSize(PixelSnap(cfg.combatIndicatorSize or 16), PixelSnap(cfg.combatIndicatorSize or 16))
    combatIcon:Hide()

    -- Text carrier: text band (above every border incl. the raise, below auras).
    local textCarrier = CreateFrame("Frame", nil, frame)
    textCarrier:SetAllPoints(health)
    textCarrier:SetFrameLevel(frame:GetFrameLevel() + mod.LVL_TEXT)
    -- The texts are built on it by ApplyPreviewData (ns.RF_TextPreview).
    frame.textCarrier = textCarrier

    -- Status text (DEAD / OFFLINE / AFK)
    local statusFS = textCarrier:CreateFontString(nil, "OVERLAY")
    local pvStc = cfg.statusTextColor or { r = 1, g = 1, b = 1 }
    ApplyFont(statusFS, cfg.statusTextSize or 14)
    statusFS:SetJustifyH("CENTER")
    statusFS:SetTextColor(pvStc.r, pvStc.g, pvStc.b)
    statusFS:Hide()

    -- Role icon. Carrier sits just BELOW the aura band and above the base border
    -- (mirrors the real frames): clears the general border while auras draw over
    -- it; the hover/target border raise intentionally covers it.
    local roleCarrier = CreateFrame("Frame", nil, frame)
    roleCarrier:SetAllPoints(health)
    roleCarrier:SetFrameLevel(frame:GetFrameLevel() + (mod.LVL_AURA - 1))
    local roleIcon = roleCarrier:CreateTexture(nil, "OVERLAY")
    local riSz = PixelSnap(cfg.roleIconSize or 14)
    roleIcon:SetSize(riSz, riSz)

    -- Leader icon: on the text carrier band (above the general border, below the
    -- aura layer) to mirror the real frames -- the hover/target raise covers it,
    -- the general border does not.
    local leaderIcon = textCarrier:CreateTexture(nil, "OVERLAY")
    local liSz = PixelSnap(cfg.leaderIconSize or 14)
    leaderIcon:SetSize(liSz, liSz)
    local liPos = (cfg.leaderIconPosition or "top"):upper()
    leaderIcon:SetPoint(
        liPos,
        mod.RF_AnchorHost(health, cfg),
        liPos,
        cfg.leaderIconOffsetX or 0,
        cfg.leaderIconOffsetY or 0
    )
    leaderIcon:Hide()

    -- Top Name Bar (preview; sized/styled by ApplyPreviewData)
    local tnb = CreateFrame("Frame", nil, frame)
    tnb:SetFrameLevel(frame:GetFrameLevel() + 4)
    tnb:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    tnb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tnb:SetHeight(PixelSnap(cfg.topNameBarHeight or 20))
    local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
    tnbBg:SetAllPoints()
    if Pix then Pix.DisablePixelSnap(tnbBg) end
    local tnbText = tnb:CreateFontString(nil, "OVERLAY")
    ApplyFont(tnbText, cfg.topNameBarTextSize or 11)
    tnbText:SetWordWrap(false)
    tnb:Hide()

    -- Store references
    frame._bg = backdrop
    frame._health = health
    frame._absorbBar = absorbBar
    frame._power = power
    frame._border = bdrFrame
    frame._threatFrame = threatFrame
    -- Stock styles: the stock edge, highlights and divider (our frame), or
    -- the Party Frames kit (host, art, portrait; stamps health._cuiKitRef
    -- here, before any refresh anchors to the host).
    if kit then
        mod.RF_KitBuild(frame, frame, health, power, bdrFrame)
    elseif mod.RF_Stock() then
        mod.RF_StockBuild(frame, frame, power)
    end
    frame._dispelBdrFrame = dispelBdrFrame
    frame._dispelOLTex = dispelOLTex
    frame._dispelIcon = dispelIconFrame
    frame._dispelIconTex = dispelIconTex
    frame._raidMarker = raidMarker
    frame._readyCheck = readyCheck
    frame._topNameBar = tnb
    frame._topNameBarBg = tnbBg
    frame._topNameBarText = tnbText
    frame._statusText = statusFS
    frame._roleIcon = roleIcon
    frame._leaderIcon = leaderIcon
    frame._combatIcon = combatIcon

    -- Helper: create a preview aura icon with texture, cooldown, border
    local function MakePreviewAuraIcon(hostFrame, level, sz)
        local di = CreateFrame("Frame", nil, hostFrame)
        di:SetFrameLevel(level)
        di:SetSize(sz, sz)
        di:Hide()
        local dt = di:CreateTexture(nil, "ARTWORK")
        dt:SetAllPoints()
        dt:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        di._tex = dt
        local cd = CreateFrame("Cooldown", nil, di, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetDrawEdge(false)
        cd:SetDrawSwipe(true)
        cd:SetSwipeColor(0, 0, 0, 0.6)
        cd:SetReverse(true)
        cd:SetHideCountdownNumbers(true)
        di._cooldown = cd
        local dbdr = CreateFrame("Frame", nil, di)
        dbdr:SetAllPoints()
        dbdr:SetFrameLevel(di:GetFrameLevel() + 1)
        if Pix then Pix.CreateBorder(dbdr, 0, 0, 0, 1, 1) end
        di._borderFrame = dbdr
        local countCarrier = CreateFrame("Frame", nil, di)
        countCarrier:SetAllPoints()
        countCarrier:SetFrameLevel(math.max(cd:GetFrameLevel() + 2, dbdr:GetFrameLevel() + 1))
        local fpInit = (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local countFS = countCarrier:CreateFontString(nil, "OVERLAY")
        countFS:SetPoint("BOTTOMRIGHT", di, "BOTTOMRIGHT", 1, -1)
        CludesUI.ApplyIconTextFont(countFS, fpInit, 8, "raidFrames")
        countFS:SetTextColor(1, 1, 1)
        countFS:SetText("")
        di._count = countFS
        -- Duration text (on same carrier above cooldown swipe)
        local durFS = countCarrier:CreateFontString(nil, "OVERLAY")
        durFS:SetPoint("CENTER", di, "CENTER", 0, 0)
        CludesUI.ApplyIconTextFont(durFS, fpInit, 8, "raidFrames")
        durFS:SetTextColor(1, 1, 1)
        durFS:Hide()
        di._durText = durFS
        return di
    end

    -- Debuff preview icons. Pool sized to the max debuffCap (8) so the player
    -- frame can showcase a full wrapping layout; only a few are shown otherwise.
    frame._pvDebuffs = {}
    for index = 1, 8 do
        frame._pvDebuffs[index] =
            MakePreviewAuraIcon(frame, frame:GetFrameLevel() + mod.LVL_AURA, mod.RFC_DebuffSize(cfg))
    end

    -- Static dispel debuff icon (shown when dispel eyeball is on)
    frame._pvDispelDebuff =
        MakePreviewAuraIcon(frame, frame:GetFrameLevel() + mod.LVL_AURA, mod.RFC_DebuffSize(cfg))

    -- Defensive preview icons
    frame._pvDefs = {}
    for index = 1, 4 do
        frame._pvDefs[index] =
            MakePreviewAuraIcon(frame, frame:GetFrameLevel() + mod.LVL_AURA, cfg.defSize or 22)
    end

    -- Buff preview icons (test mode: configured buffs cycled across frames)
    frame._pvBuffs = {}
    for index = 1, 8 do
        frame._pvBuffs[index] = MakePreviewAuraIcon(frame, frame:GetFrameLevel() + mod.LVL_AURA, 18)
    end

    return frame
end

local function GetOrCreatePreviewFrame(index)
    if not previewFrames[index] then previewFrames[index] = CreatePreviewFrame(index) end
    return previewFrames[index]
end

Inner.CreatePreviewFrame, Inner.GetOrCreatePreviewFrame = CreatePreviewFrame, GetOrCreatePreviewFrame
Inner.previewGroupLabels = previewGroupLabels
Inner.broken = false
