if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_AuraBuffReminders_Icons.lua
--
--  The icon pools (secure, combat, cursor), the provider cast button, the
--  glows, the shared icon decorations, the icon factory and the entry
--  setup.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._abrInternals
-- CludesUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local floor, max = math.floor, math.max

local _B, DEFAULT_TEXT_COLOR, REMIND = Inner._B, Inner.DEFAULT_TEXT_COLOR, Inner.EABR
local GetPlayerClass, GetTextAnchorPoints = Inner.GetPlayerClass, Inner.GetTextAnchorPoints
local InCombat, Known, ResolveFontPath = Inner.InCombat, Inner.Known, Inner.ResolveFontPath
local ResolveGlowTint, SetABRFont, SpellName, Tex =
    Inner.ResolveGlowTint, Inner.SetABRFont, Inner.SpellName, Inner.Tex
local RAID_BUFFS, _dismissedUntilLoad = Inner.RAID_BUFFS, Inner._dismissedUntilLoad
local GLOW_VIEW, StopAllGlows = Inner.GLOW_VIEW, Inner.StopAllGlows

local db
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    db = val
end

-------------------------------------------------------------------------------
--  Icon Pool SecureActionButton based for click-to-cast
-------------------------------------------------------------------------------
local ICON_SIZE = 40
local iconAnchor
Inner.iconAnchorSetters[#Inner.iconAnchorSetters + 1] = function(val)
    iconAnchor = val
end
local iconPool = {} -- all created icon buttons
local activeIcons = {} -- currently visible icons

-- Shape settings are shared with the split runtime and load-on-demand options.
do
    function mod.IconShapeValues()
        if not mod._iconShapeValues then
            mod._iconShapeValues = {
                none = "None",
                cropped = "Cropped",
                square = "Square",
                circle = "Circle",
                csquare = "Curved Square",
                diamond = "Diamond",
                hexagon = "Hexagon",
                portrait = "Portrait",
                shield = "Shield",
            }
            mod._iconShapeOrder = {
                "none",
                "cropped",
                "---",
                "square",
                "circle",
                "csquare",
                "diamond",
                "hexagon",
                "portrait",
                "shield",
            }
        end
        return mod._iconShapeValues, mod._iconShapeOrder
    end

    function mod.IconShapeMasked(p)
        local shape = p and p.iconShape
        return shape and shape ~= "none" and shape ~= "cropped" and CludesUI.SHAPE_MASKS[shape] ~= nil
    end

    function mod.CropPercent(p)
        local pct = tonumber(p and p.iconCropPercent) or 10
        if pct < 5 then
            pct = 5
        elseif pct > 25 then
            pct = 25
        end
        return pct
    end

    function mod.IconDimensions(size, p)
        if p and p.iconShape == "cropped" then
            return size, math.floor(size * (1 - 2 * mod.CropPercent(p) / 100) + 0.5)
        end
        if mod.IconShapeMasked(p) then
            return size + 8, size + 8
        end
        return size, size
    end

    -- Only addon-owned icons reach this helper. Secure owners are gated by the caller.
    function mod.ApplyIconShape(frame, p)
        if not (frame and frame._icon) then
            return
        end
        local shape = (p and p.iconShape) or "none"
        local masked = mod.IconShapeMasked(p)
        local zoom = (p and p.iconZoom) or 0.07
        local crop = shape == "cropped" and mod.CropPercent(p) or 0
        local inset = masked and ((p and p.borderSize) or 1) > 0 and 1 or 0
        local status = frame._eabrShape
        if not status then
            if shape == "none" and not (p and p.iconZoom) then
                return
            end
            status = {}
            frame._eabrShape = status
        end
        if
            status.shape == shape
            and status.zoom == zoom
            and status.crop == crop
            and status.inset == inset
            and status.highlight == frame._hl
        then
            return
        end
        local iconTex = frame._icon
        if masked then
            if not status.mask then
                status.mask = frame:CreateMaskTexture()
            end
            status.mask:SetTexture(
                CludesUI.SHAPE_MASKS[shape],
                "CLAMPTOBLACKADDITIVE",
                "CLAMPTOBLACKADDITIVE"
            )
            status.mask:ClearAllPoints()
            if inset > 0 then
                -- CDM keeps the icon inside the ring; the ring itself is unmasked.
                CludesUI.PP.Point(status.mask, "TOPLEFT", frame, "TOPLEFT", inset, -inset)
                CludesUI.PP.Point(status.mask, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
            else
                status.mask:SetAllPoints(frame)
            end
            status.mask:Show()
            if not status.attached then
                iconTex:AddMaskTexture(status.mask)
                status.attached = true
            end
            if frame._hl and (status.highlight ~= frame._hl or not status.highlightAttached) then
                frame._hl:AddMaskTexture(status.mask)
                status.highlightAttached = true
            end
            if not status.glowExtra then
                status.glowExtra = {}
            end
            -- Outline glows extend beyond the inset icon mask, like CDM's proc glows.
            status.glowExtra.shapeMask = status.mask
            status.glowExtra.maskPath = CludesUI.SHAPE_MASKS[shape]
            status.glowExtra.borderPath = CludesUI.SHAPE_BORDERS[shape]
            local visible = (128 - 2 * (CludesUI.SHAPE_INSETS[shape] or 17)) / 128
            local half = (0.5 - zoom) / visible
            iconTex:SetTexCoord(0.5 - half, 0.5 + half, 0.5 - half, 0.5 + half)
        else
            if status.attached then
                iconTex:RemoveMaskTexture(status.mask)
                if status.highlight then
                    status.highlight:RemoveMaskTexture(status.mask)
                end
                status.attached = nil
                status.highlightAttached = nil
            end
            if status.mask then
                status.mask:Hide()
            end
            iconTex:SetTexCoord(zoom, 1 - zoom, zoom + crop / 100, 1 - zoom - crop / 100)
        end
        if iconTex.SetSnapToPixelGrid then
            iconTex:SetSnapToPixelGrid(false)
            iconTex:SetTexelSnappingBias(0)
        end
        status.shape, status.zoom, status.crop, status.highlight = shape, zoom, crop, frame._hl
        status.inset = inset
    end

    function mod.IconGlowExtra(frame, panelFrame)
        local status = frame._eabrShape
        if status and status.attached then
            status.glowExtra.panel = panelFrame or nil
            return status.glowExtra
        end
        return panelFrame and CludesUI.Glows.PANEL_EXTRA or nil
    end

    -- Secure icons are skipped in combat (ApplyIconBorder); the combat-end
    -- refresh lays them out again with the shape.
    function mod.RefreshIconShapes()
        Inner.EABR.ApplyAllIconBorders()
        if _G._CUABR_RequestRefresh then
            _G._CUABR_RequestRefresh()
        end
    end
end

-- Talent icon state moved to CludesUIABR_TalentReminders.lua

-------------------------------------------------------------------------------
--  Combat Icon Pool -- non-secure frames for visual-only display during combat.
-------------------------------------------------------------------------------
local combatAnchor -- created in OnEnable, follows iconAnchor position
Inner.combatAnchorSetters[#Inner.combatAnchorSetters + 1] = function(val)
    combatAnchor = val
end
local combatIconPool = {}
local receiverIconPool = {} -- a groupmate's raid buff the player cannot cast
local combatActiveIcons = {}

-------------------------------------------------------------------------------
--  Cursor-attached combat icons -- shown at cursor when cursorAttach is enabled.
-------------------------------------------------------------------------------
local CURSOR_IMPORTANT = {
    -- PROVIDER raid buffs are important (cat == "raidbuff" + mode "spell" --
    -- see IsImportantBuff): a buff YOU can cast that the group is missing.
    -- Receiver-view reminders (a groupmate's buff the player lacks) never
    -- ride the cursor -- nothing there is actionable by the player's own
    -- hands. Beacon tracking uses its own independent system (_B); beacons
    -- are the player's own casts, so their cursor treatment already fits.
}
local cursorAnchor
Inner.cursorAnchorSetters[#Inner.cursorAnchorSetters + 1] = function(val)
    cursorAnchor = val
end
local cursorIconPool = {}
local cursorActiveIcons = {}

local function GetStrata()
    return db and db.profile.display.frameStrata or "MEDIUM"
end

-- Borders live on a dedicated visual child instead of on the reminder
-- button itself. Besides allowing Border Size 0 without hiding the icon, this
-- keeps all BackdropTemplate work away from secure action attributes. Secure
-- owners are never created/restyled under combat lockdown; visual-only combat
-- and cursor icons can still update immediately.
-- The options page frame pool's table (the parent makes it, the options addon
-- fills it in place when it loads the pool), captured once at load as the
-- core's paths capture it, so a later write to the public slot never reaches
-- this path. A block local.
do
    local POOL = CludesUI._Pool
    function REMIND.ApplyIconBorder(frame, protectedOwner)
        if not frame or (protectedOwner and InCombatLockdown()) then
            return
        end
        local p = db and db.profile and db.profile.display
        if (p and ((p.iconShape and p.iconShape ~= "none") or p.iconZoom)) or frame._eabrShape then
            mod.ApplyIconShape(frame, p)
        end
        local border = frame._eabrBorderFrame
        if not border then
            -- The options preview icons are frames of the options page pool, so
            -- their border comes from it too; a live reminder icon gets a plain
            -- new frame.
            border = POOL.CreateFrame("Frame", nil, frame)
            border:SetAllPoints()
            border:EnableMouse(false)
            frame._eabrBorderFrame = border
        end

        local size = (p and p.borderSize) or 1
        local texture = (p and p.borderTexture) or "solid"
        local red, green, blue, a =
            (p and p.borderR) or 0, (p and p.borderG) or 0, (p and p.borderB) or 0, (p and p.borderA) or 1
        local ox, oy = p and p.borderTextureOffset, p and p.borderTextureOffsetY
        local sx, sy = p and p.borderTextureShiftX, p and p.borderTextureShiftY
        local behind = p and p.borderBehind == true
        -- +2: the strips sit one level up (PP.CreateBorder), below the glow
        -- wrapper (+4), so a 1px glow is never hidden under a 1px border.
        local level = behind and max(0, frame:GetFrameLevel() - 1) or (frame:GetFrameLevel() + 2)
        -- Exact size companion, memoized raw: it only counts while paired with size + texture.
        local pxRaw = p and p.borderSizePx

        if p and p.iconShape and p.iconShape ~= "none" and mod.IconShapeMasked(p) then
            -- Shape art has its own thickness units; never send it through the
            -- rectangular border cache, which must repaint after switching back.
            if border._eabrSize ~= nil then
                CludesUI.ApplyBorderStyle(border, 0, red, green, blue, a, "solid")
                border._eabrSize = nil
            end
            border:SetFrameLevel(level)
            -- Clearing rectangular art at size zero also hides its host.
            if not border:IsShown() then
                border:Show()
            end
            CludesUI.PP:ApplyMaskedShapeBorder(
                border,
                nil,
                CludesUI.SHAPE_BORDERS[p.iconShape],
                size > 0 and 7 or 0,
                red,
                green,
                blue,
                a
            )
            return
        elseif frame._eabrShape then
            CludesUI.PP:HideMaskedShapeBorder(border)
        end

        -- Layout refreshes can be frequent in a raid. Restyle only when an actual
        -- setting or owner-level change occurred; size changes are handled by the
        -- border frame's anchors/BackdropTemplate size hook.
        if
            border._eabrSize == size
            and border._eabrTexture == texture
            and border._eabrPx == pxRaw
            and border._eabrR == red
            and border._eabrG == green
            and border._eabrB == blue
            and border._eabrA == a
            and border._eabrOX == ox
            and border._eabrOY == oy
            and border._eabrSX == sx
            and border._eabrSY == sy
            and border._eabrBehind == behind
            and border._eabrLevel == level
        then
            return
        end

        border:SetFrameLevel(level)
        CludesUI.ApplyBorderStyle(
            border,
            size,
            red,
            green,
            blue,
            a,
            texture,
            ox,
            oy,
            sx,
            sy,
            "aurabuffreminders",
            size,
            nil,
            CludesUI.BorderPx(pxRaw, size, texture)
        )
        border._eabrSize, border._eabrTexture, border._eabrPx = size, texture, pxRaw
        border._eabrR, border._eabrG, border._eabrB, border._eabrA = red, green, blue, a
        border._eabrOX, border._eabrOY, border._eabrSX, border._eabrSY = ox, oy, sx, sy
        border._eabrBehind, border._eabrLevel = behind, level
    end
end

function REMIND.ApplyAllIconBorders()
    for _, frame in pairs(iconPool) do
        REMIND.ApplyIconBorder(frame, true)
    end
    for _, frame in pairs(combatIconPool) do
        REMIND.ApplyIconBorder(frame, false)
    end
    for _, frame in pairs(receiverIconPool) do
        REMIND.ApplyIconBorder(frame, false)
    end
    for _, frame in pairs(cursorIconPool) do
        REMIND.ApplyIconBorder(frame, false)
    end
    if REMIND._providerCastBtn then
        REMIND.ApplyIconBorder(REMIND._providerCastBtn, true)
    end
    if _B.icons then
        for _, frame in pairs(_B.icons) do
            REMIND.ApplyIconBorder(frame, false)
        end
    end
end

function REMIND.GetIconTextOverlay(frame)
    if frame._textOverlay then
        return frame._textOverlay
    end
    local overlayFrame = CreateFrame("Frame", nil, frame)
    overlayFrame:SetAllPoints()
    overlayFrame:SetFrameLevel(frame:GetFrameLevel() + 5)
    frame._textOverlay = overlayFrame
    return overlayFrame
end

local function BuildCombatIcon(name)
    local frame = CreateFrame("Frame", name, combatAnchor)
    frame:SetSize(ICON_SIZE, ICON_SIZE)
    frame:SetFrameStrata(GetStrata())
    frame:SetFrameLevel(120)
    frame:Hide()
    local iconTex = frame:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame._icon = iconTex
    REMIND.ApplyIconBorder(frame, false)
    local textValue = REMIND.GetIconTextOverlay(frame):CreateFontString(nil, "OVERLAY")
    textValue:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    SetABRFont(textValue, ResolveFontPath(), 11)
    textValue:SetTextColor(1, 1, 1, 1)
    frame._text = textValue
    REMIND.CreateIconCountOverlay(frame)
    REMIND.CreateIconQualityOverlay(frame)
    REMIND.CreateIconBagCountOverlay(frame)
    REMIND.AttachIconHover(frame)
    REMIND.AttachIconTooltip(frame)
    REMIND.AttachCombatClickHint(frame)
    return frame
end

local function GetOrCreateCombatIcon(index)
    local frame = combatIconPool[index]
    if not frame then
        frame = BuildCombatIcon("EABR_CombatIcon" .. index)
        combatIconPool[index] = frame
    end
    return frame
end

-- A groupmate's raid buff the player cannot cast is shown to be read, never
-- clicked: its icon lets the left and right click through to whatever is
-- behind, keeps the middle-click dismiss and shows no hover highlight. Click
-- routing (SetPassThroughButtons) is blocked in combat on every frame, ours
-- included, so these icons have a pool of their own whose routing is set once,
-- out of combat. One first built in combat lets every click through (no
-- dismiss) until HideCombatIcons routes it once combat is over.
local receiversUnrouted = false
local function RouteReceiverIcon(frame)
    if InCombatLockdown() then
        frame:SetMouseClickEnabled(false)
        receiversUnrouted = true
        return
    end
    frame:SetPassThroughButtons("LeftButton", "RightButton")
    frame:SetMouseClickEnabled(true)
    frame._routed = true
end

local function GetOrCreateReceiverIcon(index)
    local frame = receiverIconPool[index]
    if not frame then
        frame = BuildCombatIcon("EABR_ReceiverIcon" .. index)
        REMIND.SetIconHighlight(frame, false)
        RouteReceiverIcon(frame)
        receiverIconPool[index] = frame
    end
    return frame
end

-- Icons of each pool shown by the current combat pass.
local combatShown, receiversShown = 0, 0

local function HideCombatIcons()
    for index = 1, #combatActiveIcons do
        local frame = combatActiveIcons[index]
        if frame then
            REMIND.ClearEatingVisual(frame)
            if frame._eabrGlowWrapper then
                frame._eabrGlowWrapper:Hide()
            end
            frame._text:SetText("")
            frame:Hide()
        end
    end
    wipe(combatActiveIcons)
    combatShown, receiversShown = 0, 0
    if receiversUnrouted and not InCombatLockdown() then
        receiversUnrouted = false
        for _, frame in pairs(receiverIconPool) do
            if not frame._routed then
                RouteReceiverIcon(frame)
            end
        end
    end
    if REMIND.SetProviderCastCombatVisible then
        REMIND.SetProviderCastCombatVisible(false)
    end
    if combatAnchor then
        CludesUI.SetElementVisibility(combatAnchor, false)
    end
end

local function ShowCombatIcon(m)
    local frame
    if REMIND.IsReceiverRaidBuff(m) then
        receiversShown = receiversShown + 1
        frame = GetOrCreateReceiverIcon(receiversShown)
    else
        combatShown = combatShown + 1
        frame = GetOrCreateCombatIcon(combatShown)
    end
    frame._dismissKey = m.dismissKey or nil
    local spellId = m.spellID or (m.data and m.data.castSpell)
    frame._icon:SetTexture(m.texture or (spellId and Tex(spellId)) or 134400)
    local profile = db and db.profile.display
    if profile and profile.showText and not m.isEating then
        local tc = profile.textColor or DEFAULT_TEXT_COLOR
        local fontFile = ResolveFontPath(profile.nameFont)
        local textSize = profile.textSize or 11
        local xOff = profile.textXOffset or 0
        local yOff = profile.textYOffset or -2
        SetABRFont(frame._text, fontFile, textSize)
        frame._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(profile)
        frame._text:SetPoint(tp, frame, ip, xOff, yOff)
        frame._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        frame._text:SetText(m.label or "")
        frame._text:Show()
    else
        frame._text:SetText("")
        frame._text:Hide()
    end
    REMIND.ApplyEatingVisual(frame, m)
    REMIND.ApplyIconExpiry(frame, m)
    REMIND.ApplyIconTooltipData(frame, m)
    REMIND.ApplyIconQuality(frame, (not m.isEating) and m.qualityAtlas or nil)
    if m.groupTotal then
        REMIND.ApplyIconGroupCoverage(frame, m.groupHave, m.groupTotal)
    else
        REMIND.ApplyIconBagCount(
            frame,
            (not m.isEating) and m.bagCount or nil,
            (not m.isEating) and m.desaturated or nil,
            (not m.isEating) and m.substitute or nil
        )
    end
    frame:Show()
    combatActiveIcons[#combatActiveIcons + 1] = frame
end

-- Left-aligned from the anchor's left edge; Grow Left right-aligns from its
-- right edge instead. Slot 0 is reserved while the provider secure button is
-- shown, and stays reserved after a mid-combat hide until the OOC park -- its
-- SetPoint/EnableMouse are protected under lockdown, so other icons must never
-- slide under it: while it is reserved Grow Left keeps the left-aligned row.
local function LayoutCombatIcons()
    local reserveSlot = REMIND._providerCastVisible or REMIND._providerCastCombatReserved
    local count = #combatActiveIcons
    if count == 0 and not reserveSlot then
        return
    end
    local p = db.profile.display
    local spacing = p.iconSpacing or 8
    local baseScale = p.scale or 1.0
    local iconSz = floor(ICON_SIZE * baseScale + 0.5)
    local iconH = iconSz
    if p.iconShape and p.iconShape ~= "none" then
        iconSz, iconH = mod.IconDimensions(iconSz, p)
    end
    local xOff = reserveSlot and (iconSz + spacing) or 0
    local pt = "TOPLEFT"
    if p.growDirection == "LEFT" and not reserveSlot then
        pt, xOff = "TOPRIGHT", -(count - 1) * (iconSz + spacing)
    end
    for index, frame in ipairs(combatActiveIcons) do
        frame:SetSize(iconSz, iconH)
        frame:SetAlpha(p.opacity or 1.0)
        REMIND.ApplyIconBorder(frame, false)
        REMIND.SizeIconQuality(frame, iconSz)
        REMIND.SizeIconBagCount(frame, iconSz)
        frame:ClearAllPoints()
        frame:SetPoint(pt, combatAnchor, pt, xOff + (index - 1) * (iconSz + spacing), 0)
    end
end

-------------------------------------------------------------------------------
--  Cursor Icon Pool: same visual style as combat icons, parented to cursorAnchor (follows the cursor frame).
-------------------------------------------------------------------------------
local function GetOrCreateCursorIcon(index)
    if cursorIconPool[index] then
        return cursorIconPool[index]
    end
    local frame = CreateFrame("Frame", "EABR_CursorIcon" .. index, cursorAnchor)
    frame:SetSize(ICON_SIZE, ICON_SIZE)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(9980)
    frame:Hide()
    local iconTex = frame:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame._icon = iconTex
    REMIND.ApplyIconBorder(frame, false)
    local textValue = REMIND.GetIconTextOverlay(frame):CreateFontString(nil, "OVERLAY")
    textValue:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    SetABRFont(textValue, ResolveFontPath(), 11)
    textValue:SetTextColor(1, 1, 1, 1)
    frame._text = textValue
    REMIND.CreateIconCountOverlay(frame)
    REMIND.CreateIconQualityOverlay(frame)
    REMIND.CreateIconBagCountOverlay(frame)
    REMIND.AttachIconHover(frame)
    REMIND.AttachIconTooltip(frame)
    REMIND.AttachCombatClickHint(frame)
    cursorIconPool[index] = frame
    return frame
end

-- Hides the cursor anchor once nothing rides it: no cursor icon and no beacon
-- placed on it (_B.onCursor). Hidden, it stops following the cursor (OnHide
-- unsubscribes); every placement shows it again.
local function ReleaseCursorAnchor()
    if cursorAnchor and #cursorActiveIcons == 0 and not _B.onCursor then
        cursorAnchor:Hide()
    end
end

local function HideCursorIcons()
    for index = 1, #cursorActiveIcons do
        local frame = cursorActiveIcons[index]
        if frame then
            REMIND.ClearEatingVisual(frame)
            if frame._eabrGlowWrapper then
                frame._eabrGlowWrapper:Hide()
            end
            frame._text:SetText("")
            frame:Hide()
        end
    end
    wipe(cursorActiveIcons)
    if cursorAnchor then
        CludesUI.SetElementVisibility(cursorAnchor, false)
    end
    ReleaseCursorAnchor()
end

local function ShowCursorIcon(iconIdx, m)
    local frame = GetOrCreateCursorIcon(iconIdx)
    frame._dismissKey = m.dismissKey or nil
    local spellId = m.spellID or (m.data and m.data.castSpell)
    frame._icon:SetTexture(m.texture or (spellId and Tex(spellId)) or 134400)
    local profile = db and db.profile.display
    if profile and profile.showText and not m.isEating then
        local tc = profile.textColor or DEFAULT_TEXT_COLOR
        local fontFile = ResolveFontPath(profile.nameFont)
        local textSize = profile.textSize or 11
        local xOff = profile.textXOffset or 0
        local yOff = profile.textYOffset or -2
        SetABRFont(frame._text, fontFile, textSize)
        frame._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(profile)
        frame._text:SetPoint(tp, frame, ip, xOff, yOff)
        frame._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        frame._text:SetText(m.label or "")
        frame._text:Show()
    else
        frame._text:SetText("")
        frame._text:Hide()
    end
    REMIND.ApplyEatingVisual(frame, m)
    REMIND.ApplyIconExpiry(frame, m)
    REMIND.ApplyIconTooltipData(frame, m)
    REMIND.ApplyIconQuality(frame, (not m.isEating) and m.qualityAtlas or nil)
    if m.groupTotal then
        REMIND.ApplyIconGroupCoverage(frame, m.groupHave, m.groupTotal)
    else
        REMIND.ApplyIconBagCount(
            frame,
            (not m.isEating) and m.bagCount or nil,
            (not m.isEating) and m.desaturated or nil,
            (not m.isEating) and m.substitute or nil
        )
    end
    frame:Show()
    cursorActiveIcons[#cursorActiveIcons + 1] = frame
end

local function LayoutCursorIcons()
    local count = #cursorActiveIcons
    if count == 0 then
        return
    end
    local p = db.profile.display
    local spacing = p.iconSpacing or 8
    local baseScale = p.scale or 1.0
    local iconSz = floor(ICON_SIZE * baseScale + 0.5)
    local iconH = iconSz
    if p.iconShape and p.iconShape ~= "none" then
        iconSz, iconH = mod.IconDimensions(iconSz, p)
    end
    local totalW = (count * iconSz) + ((count - 1) * spacing)
    local startX = -(totalW / 2) + (iconSz / 2)
    for index, frame in ipairs(cursorActiveIcons) do
        frame:SetSize(iconSz, iconH)
        frame:SetAlpha(p.opacity or 1.0)
        REMIND.ApplyIconBorder(frame, false)
        REMIND.SizeIconQuality(frame, iconSz)
        REMIND.SizeIconBagCount(frame, iconSz)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", cursorAnchor, "CENTER", startX + (index - 1) * (iconSz + spacing), 0)
    end
end

-------------------------------------------------------------------------------
--  Provider raid-buff cast button: a dedicated SecureActionButton pre-bound
--  OOC to the player's own raid buff, so the rebuff stays clickable through
--  combat (post-combat-res). Spell attributes, size and position are set out
--  of combat ONLY; in combat only alpha and child visuals change. Parented
--  to UIParent so anchor mouse states never swallow its clicks.
-------------------------------------------------------------------------------
function REMIND.LayoutProviderCastHome()
    if InCombatLockdown() then
        return
    end
    local button = REMIND._providerCastBtn
    if not button or not iconAnchor then
        return
    end
    local p = db and db.profile and db.profile.display
    local baseScale = (p and p.scale) or 1.0
    local iconSz = floor(ICON_SIZE * baseScale + 0.5)
    local iconH = iconSz
    if p and p.iconShape and p.iconShape ~= "none" then
        iconSz, iconH = mod.IconDimensions(iconSz, p)
    end
    button:SetSize(iconSz, iconH)
    REMIND.ApplyIconBorder(button, true)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", iconAnchor, "TOPLEFT", 0, 0)
    REMIND.SizeIconQuality(button, iconSz)
    REMIND.SizeIconBagCount(button, iconSz)
end

function REMIND.ParkProviderCastButton()
    local button = REMIND._providerCastBtn
    if not button then
        return
    end
    local wasVisible = REMIND._providerCastVisible
    REMIND._providerCastVisible = false
    button:SetAlpha(0)
    if button._text then
        button._text:SetText("")
        button._text:Hide()
    end
    if button._eabrGlowWrapper then
        button._eabrGlowWrapper:Hide()
    end
    if InCombatLockdown() then
        -- Slot stays reserved; move/mouse changes are protected under lockdown.
        if wasVisible or REMIND._providerCastCombatReserved then
            REMIND._providerCastCombatReserved = true
        end
        return
    end
    REMIND._providerCastCombatReserved = false
    button:EnableMouse(false)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
end

function REMIND.EnsureProviderCastButton()
    if REMIND._providerCastBtn then
        return REMIND._providerCastBtn
    end
    if not iconAnchor or InCombatLockdown() then
        return nil
    end
    local button = CreateFrame("Button", "EABR_ProviderCast", UIParent, "SecureActionButtonTemplate")
    button:SetSize(ICON_SIZE, ICON_SIZE)
    button:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "MiddleButtonUp")
    securecallfunction(button.SetPassThroughButtons, button, "RightButton")
    button:SetAttribute("useOnKeyDown", false)
    button:SetFrameStrata(GetStrata())
    button:SetFrameLevel(120)
    button:HookScript("PostClick", function(self, btnFrame)
        if btnFrame == "MiddleButton" and self._dismissKey then
            _dismissedUntilLoad[self._dismissKey] = true
            if _G._CUABR_RequestRefresh then
                _G._CUABR_RequestRefresh()
            end
        end
    end)
    local iconTex = button:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button._icon = iconTex
    REMIND.ApplyIconBorder(button, true)
    local textValue = REMIND.GetIconTextOverlay(button):CreateFontString(nil, "OVERLAY")
    textValue:SetPoint("TOP", button, "BOTTOM", 0, -2)
    SetABRFont(textValue, ResolveFontPath(), 11)
    textValue:SetTextColor(1, 1, 1, 1)
    button._text = textValue
    REMIND.CreateIconCountOverlay(button)
    REMIND.CreateIconQualityOverlay(button)
    REMIND.CreateIconBagCountOverlay(button)
    REMIND.AttachIconHover(button)
    REMIND.AttachIconTooltip(button)
    button:Show()
    REMIND._providerCastBtn = button
    REMIND._providerCastVisible = false
    REMIND.ParkProviderCastButton()
    return button
end

-- Binds the player's own castable raid buff to the button (OOC only), so the
-- binding is already warm when combat starts. WoW Forever binds the cast its
-- Raid Buffs pass picked (a rank and the member to cast it on) and builds the
-- button only once there is one.
function REMIND.SyncProviderCastSpell()
    if InCombatLockdown() then
        return
    end
    local spellId, unitToken
    if REMIND.FOREVER then
        spellId, unitToken = REMIND._fvCastSpell, REMIND._fvCastUnit
        if not (spellId or REMIND._providerCastBtn) then
            return
        end
    end
    local button = REMIND.EnsureProviderCastButton()
    if not button then
        return
    end
    if not REMIND.FOREVER then
        local playerClass = GetPlayerClass()
        for _, buff in ipairs(RAID_BUFFS) do
            if buff.class == playerClass and buff.check == "raid" and Known(buff.castSpell) then
                spellId = buff.castSpell
                break
            end
        end
    end
    unitToken = unitToken or "player" -- explicit unit so casting doesn't depend on your current target
    -- Attribute writes are skipped when the resolved cast is unchanged
    -- (this runs on every OOC refresh). Invalidation inputs: the resolved
    -- spellID (covers spec/known changes via SPELLS_CHANGED refreshes) and
    -- the unit (WoW Forever's target member).
    if spellId == REMIND._providerCastSpell and unitToken == REMIND._providerCastUnit then
        if not REMIND._providerCastVisible then
            REMIND.ParkProviderCastButton()
        end
        return
    end
    REMIND._providerCastSpell = spellId
    REMIND._providerCastUnit = unitToken
    if spellId then
        button:SetAttribute("type1", "spell")
        button:SetAttribute("spell1", spellId)
        button:SetAttribute("item1", nil)
        button:SetAttribute("macrotext1", nil)
        button:SetAttribute("unit1", unitToken)
        button._icon:SetTexture(Tex(spellId) or 134400)
        button._tooltipSpell = spellId
        button._tooltipItem = nil
    end
    if not REMIND._providerCastVisible then
        REMIND.ParkProviderCastButton()
    end
end

-- Shows/hides the provider button. OOC: full place/mouse control. Combat:
-- alpha + child visuals only (EnableMouse/SetPoint are protected).
function REMIND.SetProviderCastCombatVisible(visible, m)
    local button = REMIND._providerCastBtn
    if not button then
        REMIND._providerCastVisible = false
        return
    end
    if not visible or not m or not REMIND._providerCastSpell then
        REMIND.ParkProviderCastButton()
        return
    end
    REMIND._providerCastVisible = true
    REMIND._providerCastCombatReserved = true
    button._dismissKey = m.dismissKey or nil
    local spellId = m.spellID or REMIND._providerCastSpell
    button._icon:SetTexture(m.texture or Tex(spellId) or 134400)
    REMIND.ApplyIconTooltipData(button, m)
    local p = db and db.profile and db.profile.display
    if p and p.showText then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        SetABRFont(button._text, ResolveFontPath(p.nameFont), p.textSize or 11)
        button._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        button._text:SetPoint(tp, button, ip, p.textXOffset or 0, p.textYOffset or -2)
        button._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        button._text:SetText(m.label or "")
        button._text:SetAlpha(1)
        button._text:Show()
    else
        button._text:SetText("")
        button._text:Hide()
    end
    if m.groupTotal then
        REMIND.ApplyIconGroupCoverage(button, m.groupHave, m.groupTotal)
    else
        REMIND.ApplyIconBagCount(button, nil, nil, nil)
    end
    if not InCombatLockdown() then
        REMIND.LayoutProviderCastHome()
        button:EnableMouse(true)
    end
    button:SetAlpha((p and p.opacity) or 1)
end

local function IsImportantBuff(m)
    -- Cursor-worthy = a buff YOU can cast that others are missing (provider
    -- entries, mode "spell"). The receiver view (mode "texture" -- a
    -- groupmate's buff the PLAYER lacks) stays on the normal rows.
    if m.cat == "raidbuff" then
        return m.mode == "spell"
    end
    local key = m.data and m.data.key
    return key and CURSOR_IMPORTANT[key] or false
end

-- Hides stale secure buttons via alpha=0 (safe in combat); also stops glow animations (glow wrappers are plain Frames, not secure).
local function FadeOutSecureIcons()
    for index = 1, #activeIcons do
        local button = activeIcons[index]
        if button then
            button:SetAlpha(0)
            -- A faded button still takes clicks: no buff request from it.
            button._requestKey = nil
            if button._text then
                button._text:SetAlpha(0)
            end
            if button._eabrGlowWrapper then
                StopAllGlows(button._eabrGlowWrapper)
                button._eabrGlowWrapper:SetAlpha(0)
            end
        end
    end
end

-- Full render spec from the display settings; the options preview renders the
-- same spec. nil when the glow is off.
local ApplyGlow
do
    local SPEC = {}
    local function GlowSpec(p, result)
        local shared = p and GLOW_VIEW.toShared[p.glowType or 0]
        if not shared then
            return nil
        end
        result = result or SPEC
        result.style = shared
        result.r, result.g, result.b = ResolveGlowTint(p)
        result.lines, result.thickness, result.speed = p.glowLines, p.glowThickness, p.glowSpeed
        local bgc = p.glowBackgroundColor
        result.bg = (p.glowBackground == true) or nil
        result.bgR, result.bgG, result.bgB = bgc and bgc.r, bgc and bgc.g, bgc and bgc.b
        return result
    end
    _G._CUABR_GlowSpec = GlowSpec

    -- Also clears the glow when it is off, so callers need no RemoveGlow first
    -- (that would reset StartSpecGlow's signature and restart every refresh).
    ApplyGlow = function(button, p, overrideSz)
        local specInfo = GlowSpec(p)
        if not specInfo then
            local wid = button._eabrGlowWrapper
            if wid then
                StopAllGlows(wid)
                wid:Hide()
            end
            return
        end
        if not button._eabrGlowWrapper then
            local wid = CreateFrame("Frame", nil, button)
            wid:SetAllPoints(button)
            wid:SetFrameLevel(button:GetFrameLevel() + 4)
            button._eabrGlowWrapper = wid
        end
        local wrapper = button._eabrGlowWrapper
        local sz = overrideSz or button:GetWidth() or ICON_SIZE
        local hgt, extra = sz
        if p.iconShape and p.iconShape ~= "none" then
            if overrideSz then
                sz, hgt = mod.IconDimensions(sz, p)
            else
                hgt = button:GetHeight()
            end
        end
        if button._eabrShape then
            extra = mod.IconGlowExtra(button)
        end
        CludesUI.Glows.StartSpecGlow(wrapper, specInfo, sz, hgt, "icon", extra)
        wrapper:SetAlpha(1)
        wrapper:Show()
    end
end

local function RemoveGlow(button)
    if button._eabrGlowWrapper then
        StopAllGlows(button._eabrGlowWrapper)
        button._eabrGlowWrapper:Hide()
    end
end

-------------------------------------------------------------------------------
--  Shared icon decorations (all pools): hover highlight, tooltips, combat
--  click hint, bag-count / coverage / crafted-quality badges, and the eating
--  countdown. All frames here are OURS (field writes are safe). Every helper
--  hangs on EABR.
-------------------------------------------------------------------------------
function REMIND.AttachIconHover(frame)
    if frame._eabrHoverAttached then
        return
    end
    local iconTex = frame._icon
    if frame:IsObjectType("Button") then
        local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(iconTex)
        highlight:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        highlight:SetColorTexture(1, 1, 1, 0.2)
        frame._hl = highlight
    else
        frame:EnableMouse(true)
        local highlight = frame:CreateTexture(nil, "OVERLAY")
        highlight:SetAllPoints(iconTex)
        highlight:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        highlight:SetColorTexture(1, 1, 1, 0.2)
        highlight:Hide()
        frame:HookScript("OnEnter", function(self)
            if not self._hlOff then
                highlight:Show()
            end
        end)
        frame:HookScript("OnLeave", function()
            highlight:Hide()
        end)
    end
    frame._eabrHoverAttached = true
end

-- A groupmate's raid buff the player cannot cast: shown to be read, never
-- clicked (both clients' collectors mark it cat "raidbuff" in texture mode).
function REMIND.IsReceiverRaidBuff(m)
    return m.cat == "raidbuff" and m.mode == "texture"
end

-- Per-use hover highlight: off on an icon that takes no left click, so it
-- never reads as a button. A Button draws its highlight on the HIGHLIGHT
-- layer (hidden as a texture); the plain pools gate their OnEnter on the flag.
function REMIND.SetIconHighlight(frame, enabled)
    local off = not enabled
    if frame._hlOff == off then
        return
    end
    frame._hlOff = off
    if frame._hl then
        frame._hl:SetShown(enabled)
    end
end

function REMIND.ApplyIconTooltipData(frame, m)
    if not frame then
        return
    end
    if not m then
        frame._tooltipItem = nil
        frame._tooltipSpell = nil
        frame._tooltipLabel = nil
        return
    end
    frame._tooltipItem = m.tooltipItem or m.itemID or nil
    frame._tooltipSpell = m.spellID or (m.data and m.data.castSpell) or nil
    frame._tooltipLabel = m.label or nil
end

function REMIND.ShowIconTooltip(frame)
    local skinData = db and db.profile and db.profile.display
    if not skinData or skinData.showTooltips == false then
        return
    end
    if not frame then
        return
    end
    if frame._tooltipItem or frame._tooltipSpell then
        -- Item/spell data tooltips render through GameTooltip (the only
        -- game-data renderer). pcall-armored: 12.1 restricted-tooltip ACLs
        -- can deny frame-level calls when the content turns secret.
        local success = pcall(function()
            GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
            if frame._tooltipItem then
                GameTooltip:SetItemByID(frame._tooltipItem)
            else
                GameTooltip:SetSpellByID(frame._tooltipSpell)
            end
            if frame._outOfStock then
                GameTooltip:AddLine(CludesUI.L("You don't have this item in your bags"), 1, 0.3, 0.3, true)
            elseif frame._substitute then
                GameTooltip:AddLine(
                    CludesUI.L("Your preferred food is out - using a backup you own"),
                    1,
                    0.82,
                    0,
                    true
                )
            end
            GameTooltip:Show()
        end)
        if not success then
            GameTooltip:Hide()
        end
    elseif frame._tooltipLabel and frame._tooltipLabel ~= "" then
        -- Plain-text reminders use the suite tooltip, never GameTooltip.
        CludesUI.ShowWidgetTooltip(frame, tostring(frame._tooltipLabel))
    end
end

function REMIND.HideIconTooltip(frame)
    if frame and (frame._tooltipItem or frame._tooltipSpell) then
        GameTooltip:Hide()
    else
        CludesUI.HideWidgetTooltip()
    end
end

function REMIND.AttachIconTooltip(frame)
    if frame._eabrTooltipAttached then
        return
    end
    frame:EnableMouse(true)
    frame:HookScript("OnEnter", function(self)
        REMIND.ShowIconTooltip(self)
    end)
    frame:HookScript("OnLeave", function(self)
        REMIND.HideIconTooltip(self)
    end)
    frame._eabrTooltipAttached = true
end

-- Visual-only combat/cursor icons: tell the player why left-click does nothing.
function REMIND.NotifyCombatClickDisabled()
    local nowTime = GetTime()
    if REMIND._clickHintAt and nowTime - REMIND._clickHintAt < 2.5 then
        return
    end
    REMIND._clickHintAt = nowTime
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(CludesUI.L("Click-to-use is disabled in combat"), 1.0, 0.3, 0.3, 1.0)
    end
end

-- Click to request: a left-click on a reminder of a buff a groupmate gives
-- (receiver raid buff, Healthstone) asks the group for it in chat, at most
-- once per buff every REQUEST_THROTTLE seconds. The Custom Request Text
-- replaces the default line; REQUEST_TOKEN in it (any case) becomes the
-- buff's name.
do
    local REQUEST_THROTTLE = 10
    local REQUEST_TOKEN = "[spell]"
    local TOKEN_PATTERN = "%[[Ss][Pp][Ee][Ll][Ll]%]" -- any case
    local sentAt = {}

    -- Cuts s to at most n bytes without splitting a UTF-8 character.
    local function CutBytes(text, num)
        if #text <= num then
            return text
        end
        return (text:sub(1, num):gsub("[\192-\255][\128-\191]*$", ""))
    end

    -- Custom text as saved: "|" and control characters dropped (the chat API
    -- rejects stray escape codes), trimmed, capped; nil when empty.
    local function CleanRequestText(textValue)
        if type(textValue) ~= "string" then
            return nil
        end
        textValue = CutBytes(strtrim((textValue:gsub("[%c|]", ""))), 200)
        if textValue == "" then
            return nil
        end
        return textValue
    end
    -- Custom text until the player saves their own (shows where the token goes).
    local function RequestExample()
        return CludesUI.Lf("Could I get %1$s, please?", REQUEST_TOKEN)
    end
    local function HasRequestToken(textValue)
        return textValue:find(TOKEN_PATTERN) ~= nil
    end
    _G._CUABR_REQUEST_TOKEN = REQUEST_TOKEN
    _G._CUABR_HasRequestToken = HasRequestToken
    _G._CUABR_CleanRequestText = CleanRequestText
    _G._CUABR_RequestExample = RequestExample

    local function RequestChannel()
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
            return "INSTANCE_CHAT"
        end
        if IsInRaid() then
            return "RAID"
        end
        if IsInGroup() then
            return "PARTY"
        end
    end

    function REMIND.SendBuffRequest(key, name)
        if InCombatLockdown() then
            return
        end
        local channel = RequestChannel()
        if not channel then
            return
        end
        if not name then
            return
        end
        if C_ChatInfo.InChatMessagingLockdown() then
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(
                    CludesUI.L("Buff requests cannot be sent right now"),
                    1.0,
                    0.3,
                    0.3,
                    1.0
                )
            end
            return
        end
        local nowTime = GetTime()
        if sentAt[key] and nowTime - sentAt[key] < REQUEST_THROTTLE then
            return
        end
        sentAt[key] = nowTime
        local rb = db.profile.raidBuffs
        local custom = rb.requestCustom and CleanRequestText(rb.requestText or RequestExample())
        local message
        -- Text without the token falls back to the default line.
        if custom and HasRequestToken(custom) then
            message = custom:gsub(TOKEN_PATTERN, (name:gsub("%%", "%%%%")))
        else
            message = CludesUI.Lf("%1$s, please!", name)
        end
        C_ChatInfo.SendChatMessage(CutBytes(message, 255), channel)
    end
end

-- Middle-click dismisses here too. These are plain frames rather than the OOC
-- secure buttons, so the click carries no action of its own.
function REMIND.AttachCombatClickHint(frame)
    if frame._eabrCombatClickHint then
        return
    end
    frame:EnableMouse(true)
    frame:HookScript("OnMouseUp", function(self, btnFrame)
        if btnFrame == "LeftButton" then
            REMIND.NotifyCombatClickDisabled()
        elseif btnFrame == "MiddleButton" and self._dismissKey then
            _dismissedUntilLoad[self._dismissKey] = true
            if _G._CUABR_RequestRefresh then
                _G._CUABR_RequestRefresh()
            end
        end
    end)
    frame._eabrCombatClickHint = true
end

function REMIND.CreateIconCountOverlay(frame)
    if frame._count then
        return frame._count
    end
    local count = REMIND.GetIconTextOverlay(frame):CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    count:SetPoint("CENTER", frame._icon, "CENTER", 0, 0)
    count:Hide()
    frame._count = count
    return count
end

-- Crafted-quality badge (Professions Tier 1/2/3) for a consumable, or nil.
-- Crafted quality is immutable per item, so only positive hits are cached.
REMIND._qualityAtlasCache = REMIND._qualityAtlasCache or {}
function REMIND.GetItemQualityAtlas(itemId)
    if not itemId then
        return nil
    end
    local cached = REMIND._qualityAtlasCache[itemId]
    if cached then
        return cached
    end
    local atlas
    if C_TradeSkillUI and C_TradeSkillUI.GetItemCraftedQualityByItemInfo then
        local success, q = pcall(C_TradeSkillUI.GetItemCraftedQualityByItemInfo, itemId)
        if success and q and q > 0 then
            atlas = "Professions-Icon-Quality-Tier" .. q
        end
    end
    if not atlas then
        local itemLink = select(2, C_Item.GetItemInfo(itemId))
        if itemLink then
            local suffix = itemLink:match("Quality%-[%w%-]*Tier%d")
            if suffix then
                atlas = "Professions-Icon-" .. suffix
            end
        end
    end
    if atlas then
        REMIND._qualityAtlasCache[itemId] = atlas
    end
    return atlas
end

function REMIND.CreateIconQualityOverlay(frame)
    if frame._quality then
        return frame._quality
    end
    -- Keep the crafted-quality badge above the dedicated border child, just
    -- like count/name text. This matters for the wider textured styles.
    local q = REMIND.GetIconTextOverlay(frame):CreateTexture(nil, "OVERLAY", nil, 7)
    q:Hide()
    frame._quality = q
    return q
end

function REMIND.SizeIconQuality(frame, sz)
    local q = frame._quality
    if not q or not frame._qualityAtlas then
        return
    end
    local qs = max(10, floor(sz * 0.42))
    local off = floor(sz * 0.10)
    q:SetSize(qs, qs)
    q:ClearAllPoints()
    q:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -off, -off)
end

function REMIND.ApplyIconQuality(frame, atlas)
    if not frame then
        return
    end
    REMIND.CreateIconQualityOverlay(frame)
    frame._qualityAtlas = atlas or nil
    local q = frame._quality
    if atlas then
        q:SetAtlas(atlas)
        REMIND.SizeIconQuality(frame, frame:GetWidth() or ICON_SIZE)
        q:Show()
    else
        q:Hide()
    end
end

-- Bag-count badge (how many of the consumable remain), bottom-right corner.
function REMIND.CreateIconBagCountOverlay(frame)
    if frame._bagCount then
        return frame._bagCount
    end
    local fontStr = REMIND.GetIconTextOverlay(frame):CreateFontString(nil, "OVERLAY")
    local profile = db and db.profile.display
    SetABRFont(fontStr, ResolveFontPath(profile and profile.countFont), 11)
    fontStr:Hide()
    frame._bagCount = fontStr
    return fontStr
end

function REMIND.SizeIconBagCount(frame, sz)
    local fontStr = frame._bagCount
    if not fontStr or not frame._bagCountShown then
        return
    end
    local profile = db and db.profile.display
    local base = (profile and profile.countSize) or 16
    local fsz = max(6, floor(base * (sz / ICON_SIZE) + 0.5))
    SetABRFont(fontStr, ResolveFontPath(profile and profile.countFont), fsz)
    local dx = (profile and profile.countXOffset) or 0
    local dy = (profile and profile.countYOffset) or 0
    fontStr:ClearAllPoints()
    fontStr:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", dx, dy)
end

function REMIND.ApplyIconBagCount(frame, count, outOfStock, substitute, spellRank)
    if not frame then
        return
    end
    REMIND.CreateIconBagCountOverlay(frame)
    frame._outOfStock = outOfStock and true or nil
    frame._substitute = (substitute and not outOfStock) and true or nil
    local fontStr = frame._bagCount
    local profile = db and db.profile.display
    local showCount = not profile or profile.showCount ~= false
    if showCount and outOfStock then
        frame._bagCountShown = true
        fontStr:SetText("0")
        fontStr:SetTextColor(1, 0.2, 0.2, 1)
        REMIND.SizeIconBagCount(frame, frame:GetWidth() or ICON_SIZE)
        fontStr:Show()
    elseif spellRank or (showCount and count and count > 0) then
        frame._bagCountShown = true
        fontStr:SetText(spellRank or count)
        if substitute and not spellRank then
            fontStr:SetTextColor(1, 0.82, 0, 1)
        else
            fontStr:SetTextColor(1, 1, 1, 1)
        end
        REMIND.SizeIconBagCount(frame, frame:GetWidth() or ICON_SIZE)
        fontStr:Show()
    else
        frame._bagCountShown = nil
        fontStr:SetText("")
        fontStr:Hide()
    end
end

-- Raid-buff group coverage ("12/15") on the same corner badge as item count.
function REMIND.ApplyIconGroupCoverage(frame, have, sum)
    if not frame then
        return
    end
    REMIND.CreateIconBagCountOverlay(frame)
    local fontStr = frame._bagCount
    if have ~= nil and sum and sum > 0 then
        frame._bagCountShown = true
        frame._outOfStock = nil
        frame._substitute = nil
        fontStr:SetText(have .. "/" .. sum)
        fontStr:SetTextColor(1, 1, 1, 1)
        REMIND.SizeIconBagCount(frame, frame:GetWidth() or ICON_SIZE)
        fontStr:Show()
    else
        frame._bagCountShown = nil
        fontStr:SetText("")
        fontStr:Hide()
    end
end

-------------------------------------------------------------------------------
--  Eating countdown: while the eating channel runs, the food reminder shows
--  the eating icon with a centered countdown instead of nagging mid-meal.
--  The OnUpdate exists ONLY while eating and is throttled to ~5/sec with no
--  per-tick allocation (text only rewritten on change); it self-clears at
--  expiry and requests one refresh.
-------------------------------------------------------------------------------
function REMIND.ClearEatingVisual(frame)
    if frame._eabrEatingOnUpdate then
        frame:SetScript("OnUpdate", nil)
        frame._eabrEatingOnUpdate = nil
    end
    if frame._count then
        frame._count:Hide()
    end
    if frame._expiryBinding then
        frame._expiryBinding:SetEnabled(false)
    end
    frame._eabrEatingIcon = nil
end

function REMIND.EatingTick(self, elapsed)
    self._eatingAccum = (self._eatingAccum or 0) + elapsed
    if self._eatingAccum < 0.2 then
        return
    end
    self._eatingAccum = 0
    local rem = (self._eatingExp or 0) - GetTime()
    if rem > 0 then
        local txt
        local mins = math.ceil(rem / 60)
        if mins > 1 then
            txt = mins .. "m"
        else
            txt = math.ceil(rem) .. "s"
        end
        if txt ~= self._eatingText then
            self._eatingText = txt
            self._count:SetText(txt)
        end
        self._count:Show()
        if self._text then
            self._text:Hide()
        end
    else
        self._count:Hide()
        self:SetScript("OnUpdate", nil)
        self._eabrEatingOnUpdate = nil
        if _G._CUABR_RequestRefresh then
            _G._CUABR_RequestRefresh()
        end
    end
end

function REMIND.ApplyEatingVisual(frame, m)
    REMIND.ClearEatingVisual(frame)
    if not (m and m.isEating) then
        return
    end
    REMIND.CreateIconCountOverlay(frame)
    frame._icon:SetDesaturated(false)
    frame._icon:SetTexture(133950)
    frame._eabrEatingIcon = true
    RemoveGlow(frame)
    local expTime = m.eatingExpirationTime
    if not expTime then
        return
    end
    local profile = db and db.profile.display
    local fontFile = ResolveFontPath()
    local textSize = max(14, floor(((profile and profile.textSize) or 11) * 1.15))
    SetABRFont(frame._count, fontFile, textSize)
    frame._count:SetTextColor(1, 1, 1, 1)
    frame._eatingExp = expTime
    frame._eatingText = nil
    frame._eatingAccum = 1 -- force an immediate paint on the first tick
    REMIND.EatingTick(frame, 0)
    frame._eabrEatingOnUpdate = true
    frame:SetScript("OnUpdate", REMIND.EatingTick)
end

function REMIND.ApplyIconExpiry(frame, m)
    local expireAt = m and m.expireAt
    local binding = frame._expiryBinding
    if not expireAt then
        if binding then
            binding:SetEnabled(false)
        end
        return
    end
    if not (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding) then
        return
    end
    local count = REMIND.CreateIconCountOverlay(frame)
    if not binding then
        frame._expiryDuration = C_DurationUtil.CreateDuration()
        binding = C_DurationUtil.CreateDurationTextBinding()
        binding:SetFontString(count)
        binding:SetDuration(frame._expiryDuration)
        local fmt = CludesUI.AuraKit.GetDurationFormatter(false)
        if fmt then
            binding:SetFormatter(fmt)
        end
        frame._expiryBinding = binding
    end
    local profile = db and db.profile.display
    SetABRFont(count, ResolveFontPath(), max(14, floor(((profile and profile.textSize) or 11) * 1.15)))
    count:SetTextColor(1, 1, 1, 1)
    frame._expiryDuration:SetTimeFromEnd(expireAt, m.expireTotal)
    binding:SetEnabled(true)
    count:Show()
end

local ShowForeverGroupMenu
local iconPickerStyle

local function GetOrCreateIcon(index)
    if iconPool[index] then
        return iconPool[index]
    end
    -- SecureActionButtonTemplate for click-to-cast in combat
    local button = CreateFrame("Button", "EABR_Icon" .. index, iconAnchor, "SecureActionButtonTemplate")
    button:SetSize(ICON_SIZE, ICON_SIZE)
    button:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "MiddleButtonUp", "RightButtonUp")
    securecallfunction(button.SetPassThroughButtons, button, "RightButton")
    button:SetFrameStrata(GetStrata())
    button:Hide()

    -- Middle-click dismiss: hide this reminder until the next loading screen.
    -- Right-click on a multi-pet-cycle reminder previews the next pet without
    -- casting. On a clickable spell group it opens the spell picker.
    button:HookScript("PostClick", function(self, btnFrame, down)
        if btnFrame == "MiddleButton" and self._dismissKey then
            _dismissedUntilLoad[self._dismissKey] = true
            if _G._CUABR_RequestRefresh then
                _G._CUABR_RequestRefresh()
            end
        elseif btnFrame == "LeftButton" and self._requestKey and not down then
            REMIND.SendBuffRequest(self._requestKey, self._requestName)
        elseif btnFrame == "RightButton" and self._petCycleTotal then
            REMIND._petCycleIndex = ((REMIND._petCycleIndex or 1) % self._petCycleTotal) + 1
            if _G._CUABR_RequestRefresh then
                _G._CUABR_RequestRefresh()
            end
        elseif btnFrame == "RightButton" and self._foreverGroup and not InCombat() then
            ShowForeverGroupMenu(self)
        end
    end)

    local iconTex = button:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button._icon = iconTex
    REMIND.ApplyIconBorder(button, true)

    local textValue = REMIND.GetIconTextOverlay(button):CreateFontString(nil, "OVERLAY")
    textValue:SetPoint("TOP", button, "BOTTOM", 0, -2)
    SetABRFont(textValue, ResolveFontPath(), 11)
    textValue:SetTextColor(1, 1, 1, 1)
    button._text = textValue

    REMIND.CreateIconCountOverlay(button)
    REMIND.CreateIconQualityOverlay(button)
    REMIND.CreateIconBagCountOverlay(button)
    REMIND.AttachIconHover(button)
    REMIND.AttachIconTooltip(button)

    iconPool[index] = button
    return button
end

-- The four setters below suffix every action attribute with the "1" button, so
-- only a left click resolves them. An unsuffixed "type" is equivalent to
-- "*type*" and is inherited by every button, which is what let a middle-click
-- dismiss also fire the reminder; "*type2"/"*type3" set to ATTRIBUTE_NOOP did
-- not reliably outrank it.

-- Sets icon to a plain texture with no click action (clears cast attributes OOC).
local function SetIconTexture(button, texture, labelText)
    if not InCombat() then
        button:SetAttribute("type1", nil)
        button:SetAttribute("spell1", nil)
        button:SetAttribute("item1", nil)
        button:SetAttribute("macrotext1", nil)
    end
    button._icon:SetTexture(texture or 134400)
    button._tooltipSpell = nil
    button._tooltipItem = nil
end

local function SetIconSpell(button, spellId, texture, labelText)
    if not InCombat() then
        button:SetAttribute("type1", "spell")
        button:SetAttribute("spell1", spellId)
        button:SetAttribute("item1", nil)
        button:SetAttribute("macrotext1", nil)
        button:SetAttribute("unit1", "player")
    end
    button._icon:SetTexture(texture or Tex(spellId) or 134400)
    button._tooltipSpell = spellId
    button._tooltipItem = nil
end

local function SetIconItem(button, itemId, texture, labelText)
    if not InCombat() then
        button:SetAttribute("type1", "item")
        button:SetAttribute("item1", "item:" .. itemId)
        button:SetAttribute("spell1", nil)
        button:SetAttribute("macrotext1", nil)
        button:SetAttribute("unit1", nil)
    end
    button._icon:SetTexture(texture or C_Item.GetItemIconByID(itemId) or 134400)
    button._tooltipSpell = nil
    button._tooltipItem = itemId
end

local function SetIconMacro(button, macrotext, texture, spellId)
    if not InCombat() then
        button:SetAttribute("type1", "macro")
        button:SetAttribute("macrotext1", macrotext)
        button:SetAttribute("spell1", nil)
        button:SetAttribute("item1", nil)
        button:SetAttribute("unit1", nil)
    end
    button._icon:SetTexture(texture or 134400)
    button._tooltipSpell = spellId
    button._tooltipItem = nil
end

local pickerSpellData = {}

function REMIND.ForeverPickerSpellData(ident, ranked)
    local payload = pickerSpellData[ident]
    if not payload or (ranked and not payload.rank) then
        local name = SpellName(ident)
        if not name then
            return
        end
        local subtext = C_Spell.GetSpellSubtext(ident)
        local rank = subtext and subtext:match("%d+")
        if subtext and subtext ~= "" then
            name = name .. "(" .. subtext .. ")"
        end
        -- A faded pooled button can still receive clicks during lockdown.
        payload = { macro = "/cast [@player,nocombat] " .. name, rank = rank }
        -- Retry incomplete metadata for spells with more than one known rank.
        if rank or not ranked then
            pickerSpellData[ident] = payload
        end
    end
    return payload.macro, payload.rank
end

ShowForeverGroupMenu = function(button)
    local set = button._foreverGroup
    local profile = db.profile
    local forever = profile.forever
    local prefs = set.settings
    if not set.actions then
        prefs = set
    end
    local function SaveSettings()
        if not prefs then
            prefs = {}
            set.actions[set.key] = prefs
            set.settings = prefs
        end
        return prefs
    end
    local ids, seen = {}, {}
    for _, spellId in ipairs(set.ids) do
        local castID, ranks = REMIND.ForeverGroupCastSpell(set, spellId)
        if castID and (not set.actions or C_SpellBook.IsSpellKnown(castID)) then
            local index = seen[ranks]
            if not index then
                index = #ids + 1
                seen[ranks] = index
                ids[index] = spellId
            elseif prefs and spellId == prefs.castSpellID then
                ids[index] = spellId
            end
        end
    end
    local function IsSelected(spellId)
        return button._tooltipSpell == REMIND.ForeverGroupCastSpell(set, spellId)
    end
    local function IsCurrent()
        if
            InCombat()
            or db.profile ~= profile
            or profile.forever ~= forever
            or not (forever and forever.pickerEnabled)
            or button._foreverGroup ~= set
            or not button:IsVisible()
        then
            return false
        end
        if set.actions then
            return forever and forever.classBuffActions == set.actions and set.actions[set.key] == prefs
        end
        return forever and forever.customGroups and tContains(forever.customGroups, set)
    end
    local function CanChange(spellId)
        return IsCurrent() and tContains(set.ids, spellId)
    end
    local function ApplySpell(ident, ranked)
        local macro, rank = REMIND.ForeverPickerSpellData(ident, ranked)
        if not macro then
            return
        end
        SetIconMacro(button, macro, Tex(ident), ident)
        REMIND.ApplyIconBagCount(button, nil, nil, nil, rank)
    end
    local function SelectSpell(spellId)
        if not CanChange(spellId) then
            return
        end
        local ident, ranks = REMIND.ForeverGroupCastSpell(set, spellId)
        if not ident or (set.actions and not C_SpellBook.IsSpellKnown(ident)) then
            return
        end
        SaveSettings().castSpellID = spellId
        ApplySpell(ident, #ranks > 1)
    end
    local function AddRankControl(btnFrame, spellId)
        btnFrame:AddInitializer(function(widget)
            local badge = widget:AttachFontString()
            badge:SetFontObject(NumberFontNormalSmall)
            badge:SetDrawLayer("OVERLAY", 7)
            badge:SetWidth(30)
            badge:SetJustifyH("RIGHT")
            badge:SetPoint("CENTER", widget, "CENTER", 0, -10)
            local ident, ranks = REMIND.ForeverGroupCastSpell(set, spellId)
            if not ident then
                return
            end
            local _, rank = REMIND.ForeverPickerSpellData(ident, #ranks > 1)
            badge:SetText(rank or "")
            if #ranks < 2 then
                return
            end
            widget:EnableMouseWheel(true)
            widget:SetScript("OnMouseWheel", function(_, delta)
                if delta == 0 or not CanChange(spellId) then
                    return
                end
                local current, known, at = REMIND.ForeverGroupCastSpell(set, spellId)
                if not current then
                    return
                end
                local nextRank = at + (delta > 0 and 1 or -1)
                local nextID = known[nextRank]
                if not nextID or (set.actions and not C_SpellBook.IsSpellKnown(nextID)) then
                    return
                end
                local _, rank = REMIND.ForeverPickerSpellData(nextID, true)
                if nextRank < #known and not rank then
                    return
                end
                local selected = button._tooltipSpell == current
                if nextRank < #known then
                    local saved = SaveSettings()
                    if not saved.castRanks then
                        saved.castRanks = {}
                    end
                    saved.castRanks[spellId] = nextID
                elseif prefs and prefs.castRanks then
                    prefs.castRanks[spellId] = nil
                    if not next(prefs.castRanks) then
                        prefs.castRanks = nil
                    end
                end
                if selected then
                    ApplySpell(nextID, true)
                end
                badge:SetText(rank or "")
                if GameTooltip:IsOwned(widget) then
                    GameTooltip:SetSpellByID(nextID)
                end
            end)
        end)
        btnFrame:AddResetter(function(widget)
            widget:SetScript("OnMouseWheel", nil)
            widget:EnableMouseWheel(false)
        end)
    end
    if
        #ids < 2
        or not (
            MenuUtil
            and MenuUtil.CreateContextMenu
            and MenuVariants
            and MenuConstants
            and MenuConstants.HorizontalGridDirection
        )
    then
        return
    end
    REMIND.HideIconTooltip(button)
    if not iconPickerStyle then
        local inset = { left = 4, right = 4, top = 4, bottom = 4 }
        local padding = { width = 0, height = 0 }
        iconPickerStyle = CreateFromMixins(MenuVariants.GetDefaultContextMenuMixin(), {
            GetInset = function()
                return inset
            end,
            GetChildExtentPadding = function()
                return padding
            end,
            Generate = function(widget)
                local background = widget:AttachTexture()
                background:SetAtlas("common-dropdown-bg")
                background:SetAllPoints()
                background:SetAlpha(0.925)
            end,
        })
    end
    local previousStyle = button.menuMixin
    button.menuMixin = iconPickerStyle
    local dropMenu = MenuUtil.CreateContextMenu(button, function(_, root)
        root:AddMenuReleasedCallback(function()
            REMIND.ValidateOpenPicker = nil
        end)
        local columns = math.min(#ids, max(1, floor((UIParent:GetWidth() - 32) / 42)))
        root:SetGridMode(MenuConstants.HorizontalGridDirection, columns, 2)
        -- The context menu otherwise applies a minimum width meant for text rows.
        root:SetMaximumWidth(columns * 38 + 8)
        for _, ident in ipairs(ids) do
            local btnFrame = root:CreateButton("", SelectSpell, ident)
            btnFrame:AddInitializer(function(widget, description)
                local spellId = description:GetData()
                if IsSelected(spellId) then
                    local border = widget:AttachTexture()
                    border:SetSize(38, 38)
                    border:SetPoint("CENTER")
                    border:SetColorTexture(1, 0.82, 0, 1)
                end
                local iconTex = widget:AttachTexture()
                iconTex:SetDrawLayer("ARTWORK", 1)
                iconTex:SetSize(34, 34)
                iconTex:SetPoint("CENTER")
                iconTex:SetTexture(Tex(spellId) or 134400)
                return 38, 38
            end)
            btnFrame:SetTooltip(function(tooltip, description)
                local ownerFrame = tooltip:GetOwner()
                tooltip:SetOwner(ownerFrame, "ANCHOR_NONE")
                tooltip:ClearAllPoints()
                tooltip:SetPoint("BOTTOMLEFT", ownerFrame, "TOPRIGHT", 4, 4)
                local spellId = REMIND.ForeverGroupCastSpell(set, description:GetData())
                if spellId then
                    tooltip:SetSpellByID(spellId)
                end
            end)
            AddRankControl(btnFrame, ident)
        end
    end)
    button.menuMixin = previousStyle
    if dropMenu then
        REMIND.ValidateOpenPicker = function()
            if not IsCurrent() then
                dropMenu:Close()
            end
        end
    end
    if dropMenu and not InputUtil.IsGamepadUIEnabled() then
        local anchorPoint = dropMenu:GetPoint()
        dropMenu:ClearAllPoints()
        InputUtil.AnchorRegionToCursor(dropMenu, anchorPoint == "BOTTOMLEFT" and "BOTTOM" or "TOP")
    end
end

-------------------------------------------------------------------------------
--  Data-driven setup: eliminates per-refresh closure + table allocations
-------------------------------------------------------------------------------
-- Pre-allocated entry pool + data-driven setup (eliminates per-refresh closures)
local AcquireEntry, ResetEntryPool, ApplySetup
do
    local pool = {}
    local inUse = 0

    AcquireEntry = function()
        inUse = inUse + 1
        local e = pool[inUse]
        if not e then
            e = {}
            pool[inUse] = e
        end
        e.mode = nil
        e.spellID = nil
        e.itemID = nil
        e.macro = nil
        e.texture = nil
        e.label = nil
        e.unit = nil
        e.desaturated = false
        e.tooltipItem = nil
        e.cat = nil
        e.data = nil
        e.dismissKey = nil
        e.petCycleTotal = nil
        e.isEating = nil
        e.eatingExpirationTime = nil
        e.expireAt = nil
        e.expireTotal = nil
        e.qualityAtlas = nil
        e.bagCount = nil
        e.substitute = nil
        e.groupHave = nil
        e.groupTotal = nil
        e.requestKey = nil
        e.requestName = nil
        e.foreverGroup = nil
        e.spellRank = nil
        return e
    end

    ResetEntryPool = function()
        inUse = 0
    end

    ApplySetup = function(button, m)
        local mode = m.mode
        if mode == "spell" then
            SetIconSpell(button, m.spellID, m.texture or Tex(m.spellID), m.label)
            if m.unit and not InCombat() then
                button:SetAttribute("unit1", m.unit)
            end
        elseif mode == "item" then
            SetIconItem(button, m.itemID, m.texture, m.label)
        elseif mode == "macro" then
            SetIconMacro(button, m.macro, m.texture or (m.spellID and Tex(m.spellID)), m.spellID)
            button._tooltipItem = m.tooltipItem
        else -- "texture"
            SetIconTexture(button, m.texture, m.label)
            if m.spellID then
                button._tooltipSpell = m.spellID
            end
            if m.tooltipItem then
                button._tooltipItem = m.tooltipItem
            end
        end
        button._text:SetText(m.label or "")
        button._icon:SetDesaturated(m.desaturated or false)
        button._tooltipLabel = m.label or nil
    end
end

Inner.AcquireEntry, Inner.activeIcons, Inner.ApplyGlow = AcquireEntry, activeIcons, ApplyGlow
Inner.ApplySetup, Inner.combatActiveIcons = ApplySetup, combatActiveIcons
Inner.combatIconPool, Inner.cursorActiveIcons = combatIconPool, cursorActiveIcons
Inner.receiverIconPool = receiverIconPool
Inner.FadeOutSecureIcons, Inner.GetOrCreateIcon = FadeOutSecureIcons, GetOrCreateIcon
Inner.GetStrata, Inner.HideCombatIcons, Inner.HideCursorIcons = GetStrata, HideCombatIcons, HideCursorIcons
Inner.ICON_SIZE, Inner.iconPool, Inner.IsImportantBuff = ICON_SIZE, iconPool, IsImportantBuff
Inner.LayoutCombatIcons, Inner.LayoutCursorIcons = LayoutCombatIcons, LayoutCursorIcons
Inner.RemoveGlow, Inner.ResetEntryPool, Inner.ShowCombatIcon = RemoveGlow, ResetEntryPool, ShowCombatIcon
Inner.ShowCursorIcon, Inner.ReleaseCursorAnchor = ShowCursorIcon, ReleaseCursorAnchor
Inner.broken = false
