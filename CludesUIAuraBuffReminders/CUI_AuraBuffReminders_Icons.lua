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

local floor, upper = math.floor, math.max

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

    function mod.IconDimensions(dim, p)
        if p and p.iconShape == "cropped" then
            return dim, math.floor(dim * (1 - 2 * mod.CropPercent(p) / 100) + 0.5)
        end
        if mod.IconShapeMasked(p) then
            return dim + 8, dim + 8
        end
        return dim, dim
    end

    -- Only addon-owned icons reach this helper. Secure owners are gated by the caller.
    function mod.ApplyIconShape(f, p)
        if not (f and f._icon) then
            return
        end
        local shape = (p and p.iconShape) or "none"
        local masked = mod.IconShapeMasked(p)
        local zoom = (p and p.iconZoom) or 0.07
        local crop = shape == "cropped" and mod.CropPercent(p) or 0
        local inset = masked and ((p and p.borderSize) or 1) > 0 and 1 or 0
        local status = f._eabrShape
        if not status then
            if shape == "none" and not (p and p.iconZoom) then
                return
            end
            status = {}
            f._eabrShape = status
        end
        if
            status.shape == shape
            and status.zoom == zoom
            and status.crop == crop
            and status.inset == inset
            and status.highlight == f._hl
        then
            return
        end
        local glyph = f._icon
        if masked then
            if not status.mask then
                status.mask = f:CreateMaskTexture()
            end
            status.mask:SetTexture(
                CludesUI.SHAPE_MASKS[shape],
                "CLAMPTOBLACKADDITIVE",
                "CLAMPTOBLACKADDITIVE"
            )
            status.mask:ClearAllPoints()
            if inset > 0 then
                -- CDM keeps the icon inside the ring; the ring itself is unmasked.
                CludesUI.PP.Point(status.mask, "TOPLEFT", f, "TOPLEFT", inset, -inset)
                CludesUI.PP.Point(status.mask, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
            else
                status.mask:SetAllPoints(f)
            end
            status.mask:Show()
            if not status.attached then
                glyph:AddMaskTexture(status.mask)
                status.attached = true
            end
            if f._hl and (status.highlight ~= f._hl or not status.highlightAttached) then
                f._hl:AddMaskTexture(status.mask)
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
            glyph:SetTexCoord(0.5 - half, 0.5 + half, 0.5 - half, 0.5 + half)
        else
            if status.attached then
                glyph:RemoveMaskTexture(status.mask)
                if status.highlight then
                    status.highlight:RemoveMaskTexture(status.mask)
                end
                status.attached = nil
                status.highlightAttached = nil
            end
            if status.mask then
                status.mask:Hide()
            end
            glyph:SetTexCoord(zoom, 1 - zoom, zoom + crop / 100, 1 - zoom - crop / 100)
        end
        if glyph.SetSnapToPixelGrid then
            glyph:SetSnapToPixelGrid(false)
            glyph:SetTexelSnappingBias(0)
        end
        status.shape, status.zoom, status.crop, status.highlight = shape, zoom, crop, f._hl
        status.inset = inset
    end

    function mod.IconGlowExtra(f, panelFrame)
        local status = f._eabrShape
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
    function REMIND.ApplyIconBorder(f, protectedOwner)
        if not f or (protectedOwner and InCombatLockdown()) then
            return
        end
        local p = db and db.profile and db.profile.display
        if (p and ((p.iconShape and p.iconShape ~= "none") or p.iconZoom)) or f._eabrShape then
            mod.ApplyIconShape(f, p)
        end
        local border = f._eabrBorderFrame
        if not border then
            -- The options preview icons are frames of the options page pool, so
            -- their border comes from it too; a live reminder icon gets a plain
            -- new frame.
            border = POOL.CreateFrame("Frame", nil, f)
            border:SetAllPoints()
            border:EnableMouse(false)
            f._eabrBorderFrame = border
        end

        local dim = (p and p.borderSize) or 1
        local texture = (p and p.borderTexture) or "solid"
        local r, g, b, a =
            (p and p.borderR) or 0, (p and p.borderG) or 0, (p and p.borderB) or 0, (p and p.borderA) or 1
        local ox, oy = p and p.borderTextureOffset, p and p.borderTextureOffsetY
        local sx, sy = p and p.borderTextureShiftX, p and p.borderTextureShiftY
        local behind = p and p.borderBehind == true
        -- +2: the strips sit one level up (PP.CreateBorder), below the glow
        -- wrapper (+4), so a 1px glow is never hidden under a 1px border.
        local level = behind and upper(0, f:GetFrameLevel() - 1) or (f:GetFrameLevel() + 2)
        -- Exact size companion, memoized raw: it only counts while paired with size + texture.
        local pxRaw = p and p.borderSizePx

        if p and p.iconShape and p.iconShape ~= "none" and mod.IconShapeMasked(p) then
            -- Shape art has its own thickness units; never send it through the
            -- rectangular border cache, which must repaint after switching back.
            if border._eabrSize ~= nil then
                CludesUI.ApplyBorderStyle(border, 0, r, g, b, a, "solid")
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
                dim > 0 and 7 or 0,
                r,
                g,
                b,
                a
            )
            return
        elseif f._eabrShape then
            CludesUI.PP:HideMaskedShapeBorder(border)
        end

        -- Layout refreshes can be frequent in a raid. Restyle only when an actual
        -- setting or owner-level change occurred; size changes are handled by the
        -- border frame's anchors/BackdropTemplate size hook.
        if
            border._eabrSize == dim
            and border._eabrTexture == texture
            and border._eabrPx == pxRaw
            and border._eabrR == r
            and border._eabrG == g
            and border._eabrB == b
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
            dim,
            r,
            g,
            b,
            a,
            texture,
            ox,
            oy,
            sx,
            sy,
            "aurabuffreminders",
            dim,
            nil,
            CludesUI.BorderPx(pxRaw, dim, texture)
        )
        border._eabrSize, border._eabrTexture, border._eabrPx = dim, texture, pxRaw
        border._eabrR, border._eabrG, border._eabrB, border._eabrA = r, g, b, a
        border._eabrOX, border._eabrOY, border._eabrSX, border._eabrSY = ox, oy, sx, sy
        border._eabrBehind, border._eabrLevel = behind, level
    end
end

function REMIND.ApplyAllIconBorders()
    for _, f in pairs(iconPool) do
        REMIND.ApplyIconBorder(f, true)
    end
    for _, f in pairs(combatIconPool) do
        REMIND.ApplyIconBorder(f, false)
    end
    for _, f in pairs(receiverIconPool) do
        REMIND.ApplyIconBorder(f, false)
    end
    for _, f in pairs(cursorIconPool) do
        REMIND.ApplyIconBorder(f, false)
    end
    if REMIND._providerCastBtn then
        REMIND.ApplyIconBorder(REMIND._providerCastBtn, true)
    end
    if _B.icons then
        for _, f in pairs(_B.icons) do
            REMIND.ApplyIconBorder(f, false)
        end
    end
end

function REMIND.GetIconTextOverlay(f)
    if f._textOverlay then
        return f._textOverlay
    end
    local overlayFrame = CreateFrame("Frame", nil, f)
    overlayFrame:SetAllPoints()
    overlayFrame:SetFrameLevel(f:GetFrameLevel() + 5)
    f._textOverlay = overlayFrame
    return overlayFrame
end

local function BuildCombatIcon(name)
    local f = CreateFrame("Frame", name, combatAnchor)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetFrameStrata(GetStrata())
    f:SetFrameLevel(120)
    f:Hide()
    local glyph = f:CreateTexture(nil, "ARTWORK")
    glyph:SetAllPoints()
    glyph:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f._icon = glyph
    REMIND.ApplyIconBorder(f, false)
    local textValue = REMIND.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY")
    textValue:SetPoint("TOP", f, "BOTTOM", 0, -2)
    SetABRFont(textValue, ResolveFontPath(), 11)
    textValue:SetTextColor(1, 1, 1, 1)
    f._text = textValue
    REMIND.CreateIconCountOverlay(f)
    REMIND.CreateIconQualityOverlay(f)
    REMIND.CreateIconBagCountOverlay(f)
    REMIND.AttachIconHover(f)
    REMIND.AttachIconTooltip(f)
    REMIND.AttachCombatClickHint(f)
    return f
end

local function GetOrCreateCombatIcon(slotPos)
    local f = combatIconPool[slotPos]
    if not f then
        f = BuildCombatIcon("EABR_CombatIcon" .. slotPos)
        combatIconPool[slotPos] = f
    end
    return f
end

-- A groupmate's raid buff the player cannot cast is shown to be read, never
-- clicked: its icon lets the left and right click through to whatever is
-- behind, keeps the middle-click dismiss and shows no hover highlight. Click
-- routing (SetPassThroughButtons) is blocked in combat on every frame, ours
-- included, so these icons have a pool of their own whose routing is set once,
-- out of combat. One first built in combat lets every click through (no
-- dismiss) until HideCombatIcons routes it once combat is over.
local receiversUnrouted = false
local function RouteReceiverIcon(f)
    if InCombatLockdown() then
        f:SetMouseClickEnabled(false)
        receiversUnrouted = true
        return
    end
    f:SetPassThroughButtons("LeftButton", "RightButton")
    f:SetMouseClickEnabled(true)
    f._routed = true
end

local function GetOrCreateReceiverIcon(slotPos)
    local f = receiverIconPool[slotPos]
    if not f then
        f = BuildCombatIcon("EABR_ReceiverIcon" .. slotPos)
        REMIND.SetIconHighlight(f, false)
        RouteReceiverIcon(f)
        receiverIconPool[slotPos] = f
    end
    return f
end

-- Icons of each pool shown by the current combat pass.
local combatShown, receiversShown = 0, 0

local function HideCombatIcons()
    for idx = 1, #combatActiveIcons do
        local f = combatActiveIcons[idx]
        if f then
            REMIND.ClearEatingVisual(f)
            if f._eabrGlowWrapper then
                f._eabrGlowWrapper:Hide()
            end
            f._text:SetText("")
            f:Hide()
        end
    end
    wipe(combatActiveIcons)
    combatShown, receiversShown = 0, 0
    if receiversUnrouted and not InCombatLockdown() then
        receiversUnrouted = false
        for _, f in pairs(receiverIconPool) do
            if not f._routed then
                RouteReceiverIcon(f)
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
    local f
    if REMIND.IsReceiverRaidBuff(m) then
        receiversShown = receiversShown + 1
        f = GetOrCreateReceiverIcon(receiversShown)
    else
        combatShown = combatShown + 1
        f = GetOrCreateCombatIcon(combatShown)
    end
    f._dismissKey = m.dismissKey or nil
    local spellId = m.spellID or (m.data and m.data.castSpell)
    f._icon:SetTexture(m.texture or (spellId and Tex(spellId)) or 134400)
    local p = db and db.profile.display
    if p and p.showText and not m.isEating then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontFile = ResolveFontPath(p.nameFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(f._text, fontFile, textSize)
        f._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        f._text:SetPoint(tp, f, ip, xOff, yOff)
        f._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        f._text:SetText(m.label or "")
        f._text:Show()
    else
        f._text:SetText("")
        f._text:Hide()
    end
    REMIND.ApplyEatingVisual(f, m)
    REMIND.ApplyIconExpiry(f, m)
    REMIND.ApplyIconTooltipData(f, m)
    REMIND.ApplyIconQuality(f, (not m.isEating) and m.qualityAtlas or nil)
    if m.groupTotal then
        REMIND.ApplyIconGroupCoverage(f, m.groupHave, m.groupTotal)
    else
        REMIND.ApplyIconBagCount(
            f,
            (not m.isEating) and m.bagCount or nil,
            (not m.isEating) and m.desaturated or nil,
            (not m.isEating) and m.substitute or nil
        )
    end
    f:Show()
    combatActiveIcons[#combatActiveIcons + 1] = f
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
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    local iconH = sz
    if p.iconShape and p.iconShape ~= "none" then
        sz, iconH = mod.IconDimensions(sz, p)
    end
    local xOff = reserveSlot and (sz + spacing) or 0
    local pt = "TOPLEFT"
    if p.growDirection == "LEFT" and not reserveSlot then
        pt, xOff = "TOPRIGHT", -(count - 1) * (sz + spacing)
    end
    for idx, f in ipairs(combatActiveIcons) do
        f:SetSize(sz, iconH)
        f:SetAlpha(p.opacity or 1.0)
        REMIND.ApplyIconBorder(f, false)
        REMIND.SizeIconQuality(f, sz)
        REMIND.SizeIconBagCount(f, sz)
        f:ClearAllPoints()
        f:SetPoint(pt, combatAnchor, pt, xOff + (idx - 1) * (sz + spacing), 0)
    end
end

-------------------------------------------------------------------------------
--  Cursor Icon Pool: same visual style as combat icons, parented to cursorAnchor (follows the cursor frame).
-------------------------------------------------------------------------------
local function GetOrCreateCursorIcon(slotPos)
    if cursorIconPool[slotPos] then
        return cursorIconPool[slotPos]
    end
    local f = CreateFrame("Frame", "EABR_CursorIcon" .. slotPos, cursorAnchor)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(9980)
    f:Hide()
    local glyph = f:CreateTexture(nil, "ARTWORK")
    glyph:SetAllPoints()
    glyph:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f._icon = glyph
    REMIND.ApplyIconBorder(f, false)
    local textValue = REMIND.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY")
    textValue:SetPoint("TOP", f, "BOTTOM", 0, -2)
    SetABRFont(textValue, ResolveFontPath(), 11)
    textValue:SetTextColor(1, 1, 1, 1)
    f._text = textValue
    REMIND.CreateIconCountOverlay(f)
    REMIND.CreateIconQualityOverlay(f)
    REMIND.CreateIconBagCountOverlay(f)
    REMIND.AttachIconHover(f)
    REMIND.AttachIconTooltip(f)
    REMIND.AttachCombatClickHint(f)
    cursorIconPool[slotPos] = f
    return f
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
    for idx = 1, #cursorActiveIcons do
        local f = cursorActiveIcons[idx]
        if f then
            REMIND.ClearEatingVisual(f)
            if f._eabrGlowWrapper then
                f._eabrGlowWrapper:Hide()
            end
            f._text:SetText("")
            f:Hide()
        end
    end
    wipe(cursorActiveIcons)
    if cursorAnchor then
        CludesUI.SetElementVisibility(cursorAnchor, false)
    end
    ReleaseCursorAnchor()
end

local function ShowCursorIcon(iconIdx, m)
    local f = GetOrCreateCursorIcon(iconIdx)
    f._dismissKey = m.dismissKey or nil
    local spellId = m.spellID or (m.data and m.data.castSpell)
    f._icon:SetTexture(m.texture or (spellId and Tex(spellId)) or 134400)
    local p = db and db.profile.display
    if p and p.showText and not m.isEating then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontFile = ResolveFontPath(p.nameFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(f._text, fontFile, textSize)
        f._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        f._text:SetPoint(tp, f, ip, xOff, yOff)
        f._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        f._text:SetText(m.label or "")
        f._text:Show()
    else
        f._text:SetText("")
        f._text:Hide()
    end
    REMIND.ApplyEatingVisual(f, m)
    REMIND.ApplyIconExpiry(f, m)
    REMIND.ApplyIconTooltipData(f, m)
    REMIND.ApplyIconQuality(f, (not m.isEating) and m.qualityAtlas or nil)
    if m.groupTotal then
        REMIND.ApplyIconGroupCoverage(f, m.groupHave, m.groupTotal)
    else
        REMIND.ApplyIconBagCount(
            f,
            (not m.isEating) and m.bagCount or nil,
            (not m.isEating) and m.desaturated or nil,
            (not m.isEating) and m.substitute or nil
        )
    end
    f:Show()
    cursorActiveIcons[#cursorActiveIcons + 1] = f
end

local function LayoutCursorIcons()
    local count = #cursorActiveIcons
    if count == 0 then
        return
    end
    local p = db.profile.display
    local spacing = p.iconSpacing or 8
    local baseScale = p.scale or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    local iconH = sz
    if p.iconShape and p.iconShape ~= "none" then
        sz, iconH = mod.IconDimensions(sz, p)
    end
    local totalW = (count * sz) + ((count - 1) * spacing)
    local startX = -(totalW / 2) + (sz / 2)
    for idx, f in ipairs(cursorActiveIcons) do
        f:SetSize(sz, iconH)
        f:SetAlpha(p.opacity or 1.0)
        REMIND.ApplyIconBorder(f, false)
        REMIND.SizeIconQuality(f, sz)
        REMIND.SizeIconBagCount(f, sz)
        f:ClearAllPoints()
        f:SetPoint("CENTER", cursorAnchor, "CENTER", startX + (idx - 1) * (sz + spacing), 0)
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
    local btn = REMIND._providerCastBtn
    if not btn or not iconAnchor then
        return
    end
    local p = db and db.profile and db.profile.display
    local baseScale = (p and p.scale) or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    local iconH = sz
    if p and p.iconShape and p.iconShape ~= "none" then
        sz, iconH = mod.IconDimensions(sz, p)
    end
    btn:SetSize(sz, iconH)
    REMIND.ApplyIconBorder(btn, true)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", iconAnchor, "TOPLEFT", 0, 0)
    REMIND.SizeIconQuality(btn, sz)
    REMIND.SizeIconBagCount(btn, sz)
end

function REMIND.ParkProviderCastButton()
    local btn = REMIND._providerCastBtn
    if not btn then
        return
    end
    local wasVisible = REMIND._providerCastVisible
    REMIND._providerCastVisible = false
    btn:SetAlpha(0)
    if btn._text then
        btn._text:SetText("")
        btn._text:Hide()
    end
    if btn._eabrGlowWrapper then
        btn._eabrGlowWrapper:Hide()
    end
    if InCombatLockdown() then
        -- Slot stays reserved; move/mouse changes are protected under lockdown.
        if wasVisible or REMIND._providerCastCombatReserved then
            REMIND._providerCastCombatReserved = true
        end
        return
    end
    REMIND._providerCastCombatReserved = false
    btn:EnableMouse(false)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
end

function REMIND.EnsureProviderCastButton()
    if REMIND._providerCastBtn then
        return REMIND._providerCastBtn
    end
    if not iconAnchor or InCombatLockdown() then
        return nil
    end
    local btn = CreateFrame("Button", "EABR_ProviderCast", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "MiddleButtonUp")
    securecallfunction(btn.SetPassThroughButtons, btn, "RightButton")
    btn:SetAttribute("useOnKeyDown", false)
    btn:SetFrameStrata(GetStrata())
    btn:SetFrameLevel(120)
    btn:HookScript("PostClick", function(self, btnFrame)
        if btnFrame == "MiddleButton" and self._dismissKey then
            _dismissedUntilLoad[self._dismissKey] = true
            if _G._CUABR_RequestRefresh then
                _G._CUABR_RequestRefresh()
            end
        end
    end)
    local glyph = btn:CreateTexture(nil, "ARTWORK")
    glyph:SetAllPoints()
    glyph:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn._icon = glyph
    REMIND.ApplyIconBorder(btn, true)
    local textValue = REMIND.GetIconTextOverlay(btn):CreateFontString(nil, "OVERLAY")
    textValue:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    SetABRFont(textValue, ResolveFontPath(), 11)
    textValue:SetTextColor(1, 1, 1, 1)
    btn._text = textValue
    REMIND.CreateIconCountOverlay(btn)
    REMIND.CreateIconQualityOverlay(btn)
    REMIND.CreateIconBagCountOverlay(btn)
    REMIND.AttachIconHover(btn)
    REMIND.AttachIconTooltip(btn)
    btn:Show()
    REMIND._providerCastBtn = btn
    REMIND._providerCastVisible = false
    REMIND.ParkProviderCastButton()
    return btn
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
    local btn = REMIND.EnsureProviderCastButton()
    if not btn then
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
        btn:SetAttribute("type1", "spell")
        btn:SetAttribute("spell1", spellId)
        btn:SetAttribute("item1", nil)
        btn:SetAttribute("macrotext1", nil)
        btn:SetAttribute("unit1", unitToken)
        btn._icon:SetTexture(Tex(spellId) or 134400)
        btn._tooltipSpell = spellId
        btn._tooltipItem = nil
    end
    if not REMIND._providerCastVisible then
        REMIND.ParkProviderCastButton()
    end
end

-- Shows/hides the provider button. OOC: full place/mouse control. Combat:
-- alpha + child visuals only (EnableMouse/SetPoint are protected).
function REMIND.SetProviderCastCombatVisible(visible, m)
    local btn = REMIND._providerCastBtn
    if not btn then
        REMIND._providerCastVisible = false
        return
    end
    if not visible or not m or not REMIND._providerCastSpell then
        REMIND.ParkProviderCastButton()
        return
    end
    REMIND._providerCastVisible = true
    REMIND._providerCastCombatReserved = true
    btn._dismissKey = m.dismissKey or nil
    local spellId = m.spellID or REMIND._providerCastSpell
    btn._icon:SetTexture(m.texture or Tex(spellId) or 134400)
    REMIND.ApplyIconTooltipData(btn, m)
    local p = db and db.profile and db.profile.display
    if p and p.showText then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        SetABRFont(btn._text, ResolveFontPath(p.nameFont), p.textSize or 11)
        btn._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        btn._text:SetPoint(tp, btn, ip, p.textXOffset or 0, p.textYOffset or -2)
        btn._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        btn._text:SetText(m.label or "")
        btn._text:SetAlpha(1)
        btn._text:Show()
    else
        btn._text:SetText("")
        btn._text:Hide()
    end
    if m.groupTotal then
        REMIND.ApplyIconGroupCoverage(btn, m.groupHave, m.groupTotal)
    else
        REMIND.ApplyIconBagCount(btn, nil, nil, nil)
    end
    if not InCombatLockdown() then
        REMIND.LayoutProviderCastHome()
        btn:EnableMouse(true)
    end
    btn:SetAlpha((p and p.opacity) or 1)
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
    for idx = 1, #activeIcons do
        local btn = activeIcons[idx]
        if btn then
            btn:SetAlpha(0)
            -- A faded button still takes clicks: no buff request from it.
            btn._requestKey = nil
            if btn._text then
                btn._text:SetAlpha(0)
            end
            if btn._eabrGlowWrapper then
                StopAllGlows(btn._eabrGlowWrapper)
                btn._eabrGlowWrapper:SetAlpha(0)
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
    ApplyGlow = function(btn, p, overrideSz)
        local specInfo = GlowSpec(p)
        if not specInfo then
            local wid = btn._eabrGlowWrapper
            if wid then
                StopAllGlows(wid)
                wid:Hide()
            end
            return
        end
        if not btn._eabrGlowWrapper then
            local wid = CreateFrame("Frame", nil, btn)
            wid:SetAllPoints(btn)
            wid:SetFrameLevel(btn:GetFrameLevel() + 4)
            btn._eabrGlowWrapper = wid
        end
        local wrapper = btn._eabrGlowWrapper
        local sz = overrideSz or btn:GetWidth() or ICON_SIZE
        local hgt, extra = sz
        if p.iconShape and p.iconShape ~= "none" then
            if overrideSz then
                sz, hgt = mod.IconDimensions(sz, p)
            else
                hgt = btn:GetHeight()
            end
        end
        if btn._eabrShape then
            extra = mod.IconGlowExtra(btn)
        end
        CludesUI.Glows.StartSpecGlow(wrapper, specInfo, sz, hgt, "icon", extra)
        wrapper:SetAlpha(1)
        wrapper:Show()
    end
end

local function RemoveGlow(btn)
    if btn._eabrGlowWrapper then
        StopAllGlows(btn._eabrGlowWrapper)
        btn._eabrGlowWrapper:Hide()
    end
end

-------------------------------------------------------------------------------
--  Shared icon decorations (all pools): hover highlight, tooltips, combat
--  click hint, bag-count / coverage / crafted-quality badges, and the eating
--  countdown. All frames here are OURS (field writes are safe). Every helper
--  hangs on EABR.
-------------------------------------------------------------------------------
function REMIND.AttachIconHover(f)
    if f._eabrHoverAttached then
        return
    end
    local glyph = f._icon
    if f:IsObjectType("Button") then
        local hl = f:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(glyph)
        hl:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        hl:SetColorTexture(1, 1, 1, 0.2)
        f._hl = hl
    else
        f:EnableMouse(true)
        local hl = f:CreateTexture(nil, "OVERLAY")
        hl:SetAllPoints(glyph)
        hl:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        hl:SetColorTexture(1, 1, 1, 0.2)
        hl:Hide()
        f:HookScript("OnEnter", function(self)
            if not self._hlOff then
                hl:Show()
            end
        end)
        f:HookScript("OnLeave", function()
            hl:Hide()
        end)
    end
    f._eabrHoverAttached = true
end

-- A groupmate's raid buff the player cannot cast: shown to be read, never
-- clicked (both clients' collectors mark it cat "raidbuff" in texture mode).
function REMIND.IsReceiverRaidBuff(m)
    return m.cat == "raidbuff" and m.mode == "texture"
end

-- Per-use hover highlight: off on an icon that takes no left click, so it
-- never reads as a button. A Button draws its highlight on the HIGHLIGHT
-- layer (hidden as a texture); the plain pools gate their OnEnter on the flag.
function REMIND.SetIconHighlight(f, enabled)
    local offset = not enabled
    if f._hlOff == offset then
        return
    end
    f._hlOff = offset
    if f._hl then
        f._hl:SetShown(enabled)
    end
end

function REMIND.ApplyIconTooltipData(f, m)
    if not f then
        return
    end
    if not m then
        f._tooltipItem = nil
        f._tooltipSpell = nil
        f._tooltipLabel = nil
        return
    end
    f._tooltipItem = m.tooltipItem or m.itemID or nil
    f._tooltipSpell = m.spellID or (m.data and m.data.castSpell) or nil
    f._tooltipLabel = m.label or nil
end

function REMIND.ShowIconTooltip(f)
    local d = db and db.profile and db.profile.display
    if not d or d.showTooltips == false then
        return
    end
    if not f then
        return
    end
    if f._tooltipItem or f._tooltipSpell then
        -- Item/spell data tooltips render through GameTooltip (the only
        -- game-data renderer). pcall-armored: 12.1 restricted-tooltip ACLs
        -- can deny frame-level calls when the content turns secret.
        local success = pcall(function()
            GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
            if f._tooltipItem then
                GameTooltip:SetItemByID(f._tooltipItem)
            else
                GameTooltip:SetSpellByID(f._tooltipSpell)
            end
            if f._outOfStock then
                GameTooltip:AddLine(CludesUI.L("You don't have this item in your bags"), 1, 0.3, 0.3, true)
            elseif f._substitute then
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
    elseif f._tooltipLabel and f._tooltipLabel ~= "" then
        -- Plain-text reminders use the suite tooltip, never GameTooltip.
        CludesUI.ShowWidgetTooltip(f, tostring(f._tooltipLabel))
    end
end

function REMIND.HideIconTooltip(f)
    if f and (f._tooltipItem or f._tooltipSpell) then
        GameTooltip:Hide()
    else
        CludesUI.HideWidgetTooltip()
    end
end

function REMIND.AttachIconTooltip(f)
    if f._eabrTooltipAttached then
        return
    end
    f:EnableMouse(true)
    f:HookScript("OnEnter", function(self)
        REMIND.ShowIconTooltip(self)
    end)
    f:HookScript("OnLeave", function(self)
        REMIND.HideIconTooltip(self)
    end)
    f._eabrTooltipAttached = true
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
    local function CutBytes(s, num)
        if #s <= num then
            return s
        end
        return (s:sub(1, num):gsub("[\192-\255][\128-\191]*$", ""))
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
        local msg
        -- Text without the token falls back to the default line.
        if custom and HasRequestToken(custom) then
            msg = custom:gsub(TOKEN_PATTERN, (name:gsub("%%", "%%%%")))
        else
            msg = CludesUI.Lf("%1$s, please!", name)
        end
        C_ChatInfo.SendChatMessage(CutBytes(msg, 255), channel)
    end
end

-- Middle-click dismisses here too. These are plain frames rather than the OOC
-- secure buttons, so the click carries no action of its own.
function REMIND.AttachCombatClickHint(f)
    if f._eabrCombatClickHint then
        return
    end
    f:EnableMouse(true)
    f:HookScript("OnMouseUp", function(self, btnFrame)
        if btnFrame == "LeftButton" then
            REMIND.NotifyCombatClickDisabled()
        elseif btnFrame == "MiddleButton" and self._dismissKey then
            _dismissedUntilLoad[self._dismissKey] = true
            if _G._CUABR_RequestRefresh then
                _G._CUABR_RequestRefresh()
            end
        end
    end)
    f._eabrCombatClickHint = true
end

function REMIND.CreateIconCountOverlay(f)
    if f._count then
        return f._count
    end
    local count = REMIND.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    count:SetPoint("CENTER", f._icon, "CENTER", 0, 0)
    count:Hide()
    f._count = count
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

function REMIND.CreateIconQualityOverlay(f)
    if f._quality then
        return f._quality
    end
    -- Keep the crafted-quality badge above the dedicated border child, just
    -- like count/name text. This matters for the wider textured styles.
    local q = REMIND.GetIconTextOverlay(f):CreateTexture(nil, "OVERLAY", nil, 7)
    q:Hide()
    f._quality = q
    return q
end

function REMIND.SizeIconQuality(f, sz)
    local q = f._quality
    if not q or not f._qualityAtlas then
        return
    end
    local qs = upper(10, floor(sz * 0.42))
    local offset = floor(sz * 0.10)
    q:SetSize(qs, qs)
    q:ClearAllPoints()
    q:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -offset, -offset)
end

function REMIND.ApplyIconQuality(f, atlas)
    if not f then
        return
    end
    REMIND.CreateIconQualityOverlay(f)
    f._qualityAtlas = atlas or nil
    local q = f._quality
    if atlas then
        q:SetAtlas(atlas)
        REMIND.SizeIconQuality(f, f:GetWidth() or ICON_SIZE)
        q:Show()
    else
        q:Hide()
    end
end

-- Bag-count badge (how many of the consumable remain), bottom-right corner.
function REMIND.CreateIconBagCountOverlay(f)
    if f._bagCount then
        return f._bagCount
    end
    local fontStr = REMIND.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY")
    local p = db and db.profile.display
    SetABRFont(fontStr, ResolveFontPath(p and p.countFont), 11)
    fontStr:Hide()
    f._bagCount = fontStr
    return fontStr
end

function REMIND.SizeIconBagCount(f, sz)
    local fontStr = f._bagCount
    if not fontStr or not f._bagCountShown then
        return
    end
    local p = db and db.profile.display
    local baseValue = (p and p.countSize) or 16
    local fsz = upper(6, floor(baseValue * (sz / ICON_SIZE) + 0.5))
    SetABRFont(fontStr, ResolveFontPath(p and p.countFont), fsz)
    local dx = (p and p.countXOffset) or 0
    local dy = (p and p.countYOffset) or 0
    fontStr:ClearAllPoints()
    fontStr:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", dx, dy)
end

function REMIND.ApplyIconBagCount(f, count, outOfStock, substitute, spellRank)
    if not f then
        return
    end
    REMIND.CreateIconBagCountOverlay(f)
    f._outOfStock = outOfStock and true or nil
    f._substitute = (substitute and not outOfStock) and true or nil
    local fontStr = f._bagCount
    local p = db and db.profile.display
    local showCount = not p or p.showCount ~= false
    if showCount and outOfStock then
        f._bagCountShown = true
        fontStr:SetText("0")
        fontStr:SetTextColor(1, 0.2, 0.2, 1)
        REMIND.SizeIconBagCount(f, f:GetWidth() or ICON_SIZE)
        fontStr:Show()
    elseif spellRank or (showCount and count and count > 0) then
        f._bagCountShown = true
        fontStr:SetText(spellRank or count)
        if substitute and not spellRank then
            fontStr:SetTextColor(1, 0.82, 0, 1)
        else
            fontStr:SetTextColor(1, 1, 1, 1)
        end
        REMIND.SizeIconBagCount(f, f:GetWidth() or ICON_SIZE)
        fontStr:Show()
    else
        f._bagCountShown = nil
        fontStr:SetText("")
        fontStr:Hide()
    end
end

-- Raid-buff group coverage ("12/15") on the same corner badge as item count.
function REMIND.ApplyIconGroupCoverage(f, have, sum)
    if not f then
        return
    end
    REMIND.CreateIconBagCountOverlay(f)
    local fontStr = f._bagCount
    if have ~= nil and sum and sum > 0 then
        f._bagCountShown = true
        f._outOfStock = nil
        f._substitute = nil
        fontStr:SetText(have .. "/" .. sum)
        fontStr:SetTextColor(1, 1, 1, 1)
        REMIND.SizeIconBagCount(f, f:GetWidth() or ICON_SIZE)
        fontStr:Show()
    else
        f._bagCountShown = nil
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
function REMIND.ClearEatingVisual(f)
    if f._eabrEatingOnUpdate then
        f:SetScript("OnUpdate", nil)
        f._eabrEatingOnUpdate = nil
    end
    if f._count then
        f._count:Hide()
    end
    if f._expiryBinding then
        f._expiryBinding:SetEnabled(false)
    end
    f._eabrEatingIcon = nil
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

function REMIND.ApplyEatingVisual(f, m)
    REMIND.ClearEatingVisual(f)
    if not (m and m.isEating) then
        return
    end
    REMIND.CreateIconCountOverlay(f)
    f._icon:SetDesaturated(false)
    f._icon:SetTexture(133950)
    f._eabrEatingIcon = true
    RemoveGlow(f)
    local expTime = m.eatingExpirationTime
    if not expTime then
        return
    end
    local p = db and db.profile.display
    local fontFile = ResolveFontPath()
    local textSize = upper(14, floor(((p and p.textSize) or 11) * 1.15))
    SetABRFont(f._count, fontFile, textSize)
    f._count:SetTextColor(1, 1, 1, 1)
    f._eatingExp = expTime
    f._eatingText = nil
    f._eatingAccum = 1 -- force an immediate paint on the first tick
    REMIND.EatingTick(f, 0)
    f._eabrEatingOnUpdate = true
    f:SetScript("OnUpdate", REMIND.EatingTick)
end

function REMIND.ApplyIconExpiry(f, m)
    local expireAt = m and m.expireAt
    local binding = f._expiryBinding
    if not expireAt then
        if binding then
            binding:SetEnabled(false)
        end
        return
    end
    if not (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding) then
        return
    end
    local count = REMIND.CreateIconCountOverlay(f)
    if not binding then
        f._expiryDuration = C_DurationUtil.CreateDuration()
        binding = C_DurationUtil.CreateDurationTextBinding()
        binding:SetFontString(count)
        binding:SetDuration(f._expiryDuration)
        local fmt = CludesUI.AuraKit.GetDurationFormatter(false)
        if fmt then
            binding:SetFormatter(fmt)
        end
        f._expiryBinding = binding
    end
    local p = db and db.profile.display
    SetABRFont(count, ResolveFontPath(), upper(14, floor(((p and p.textSize) or 11) * 1.15)))
    count:SetTextColor(1, 1, 1, 1)
    f._expiryDuration:SetTimeFromEnd(expireAt, m.expireTotal)
    binding:SetEnabled(true)
    count:Show()
end

local ShowForeverGroupMenu
local iconPickerStyle

local function GetOrCreateIcon(slotPos)
    if iconPool[slotPos] then
        return iconPool[slotPos]
    end
    -- SecureActionButtonTemplate for click-to-cast in combat
    local btn = CreateFrame("Button", "EABR_Icon" .. slotPos, iconAnchor, "SecureActionButtonTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "MiddleButtonUp", "RightButtonUp")
    securecallfunction(btn.SetPassThroughButtons, btn, "RightButton")
    btn:SetFrameStrata(GetStrata())
    btn:Hide()

    -- Middle-click dismiss: hide this reminder until the next loading screen.
    -- Right-click on a multi-pet-cycle reminder previews the next pet without
    -- casting. On a clickable spell group it opens the spell picker.
    btn:HookScript("PostClick", function(self, btnFrame, down)
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

    local glyph = btn:CreateTexture(nil, "ARTWORK")
    glyph:SetAllPoints()
    glyph:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn._icon = glyph
    REMIND.ApplyIconBorder(btn, true)

    local textValue = REMIND.GetIconTextOverlay(btn):CreateFontString(nil, "OVERLAY")
    textValue:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    SetABRFont(textValue, ResolveFontPath(), 11)
    textValue:SetTextColor(1, 1, 1, 1)
    btn._text = textValue

    REMIND.CreateIconCountOverlay(btn)
    REMIND.CreateIconQualityOverlay(btn)
    REMIND.CreateIconBagCountOverlay(btn)
    REMIND.AttachIconHover(btn)
    REMIND.AttachIconTooltip(btn)

    iconPool[slotPos] = btn
    return btn
end

-- The four setters below suffix every action attribute with the "1" button, so
-- only a left click resolves them. An unsuffixed "type" is equivalent to
-- "*type*" and is inherited by every button, which is what let a middle-click
-- dismiss also fire the reminder; "*type2"/"*type3" set to ATTRIBUTE_NOOP did
-- not reliably outrank it.

-- Sets icon to a plain texture with no click action (clears cast attributes OOC).
local function SetIconTexture(btn, texture, labelText)
    if not InCombat() then
        btn:SetAttribute("type1", nil)
        btn:SetAttribute("spell1", nil)
        btn:SetAttribute("item1", nil)
        btn:SetAttribute("macrotext1", nil)
    end
    btn._icon:SetTexture(texture or 134400)
    btn._tooltipSpell = nil
    btn._tooltipItem = nil
end

local function SetIconSpell(btn, spellId, texture, labelText)
    if not InCombat() then
        btn:SetAttribute("type1", "spell")
        btn:SetAttribute("spell1", spellId)
        btn:SetAttribute("item1", nil)
        btn:SetAttribute("macrotext1", nil)
        btn:SetAttribute("unit1", "player")
    end
    btn._icon:SetTexture(texture or Tex(spellId) or 134400)
    btn._tooltipSpell = spellId
    btn._tooltipItem = nil
end

local function SetIconItem(btn, itemId, texture, labelText)
    if not InCombat() then
        btn:SetAttribute("type1", "item")
        btn:SetAttribute("item1", "item:" .. itemId)
        btn:SetAttribute("spell1", nil)
        btn:SetAttribute("macrotext1", nil)
        btn:SetAttribute("unit1", nil)
    end
    btn._icon:SetTexture(texture or C_Item.GetItemIconByID(itemId) or 134400)
    btn._tooltipSpell = nil
    btn._tooltipItem = itemId
end

local function SetIconMacro(btn, macrotext, texture, spellId)
    if not InCombat() then
        btn:SetAttribute("type1", "macro")
        btn:SetAttribute("macrotext1", macrotext)
        btn:SetAttribute("spell1", nil)
        btn:SetAttribute("item1", nil)
        btn:SetAttribute("unit1", nil)
    end
    btn._icon:SetTexture(texture or 134400)
    btn._tooltipSpell = spellId
    btn._tooltipItem = nil
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

ShowForeverGroupMenu = function(btn)
    local group = btn._foreverGroup
    local profile = db.profile
    local forever = profile.forever
    local prefs = group.settings
    if not group.actions then
        prefs = group
    end
    local function SaveSettings()
        if not prefs then
            prefs = {}
            group.actions[group.key] = prefs
            group.settings = prefs
        end
        return prefs
    end
    local ids, seen = {}, {}
    for _, spellId in ipairs(group.ids) do
        local castID, ranks = REMIND.ForeverGroupCastSpell(group, spellId)
        if castID and (not group.actions or C_SpellBook.IsSpellKnown(castID)) then
            local slotPos = seen[ranks]
            if not slotPos then
                slotPos = #ids + 1
                seen[ranks] = slotPos
                ids[slotPos] = spellId
            elseif prefs and spellId == prefs.castSpellID then
                ids[slotPos] = spellId
            end
        end
    end
    local function IsSelected(spellId)
        return btn._tooltipSpell == REMIND.ForeverGroupCastSpell(group, spellId)
    end
    local function IsCurrent()
        if
            InCombat()
            or db.profile ~= profile
            or profile.forever ~= forever
            or not (forever and forever.pickerEnabled)
            or btn._foreverGroup ~= group
            or not btn:IsVisible()
        then
            return false
        end
        if group.actions then
            return forever and forever.classBuffActions == group.actions and group.actions[group.key] == prefs
        end
        return forever and forever.customGroups and tContains(forever.customGroups, group)
    end
    local function CanChange(spellId)
        return IsCurrent() and tContains(group.ids, spellId)
    end
    local function ApplySpell(ident, ranked)
        local macro, rank = REMIND.ForeverPickerSpellData(ident, ranked)
        if not macro then
            return
        end
        SetIconMacro(btn, macro, Tex(ident), ident)
        REMIND.ApplyIconBagCount(btn, nil, nil, nil, rank)
    end
    local function SelectSpell(spellId)
        if not CanChange(spellId) then
            return
        end
        local ident, ranks = REMIND.ForeverGroupCastSpell(group, spellId)
        if not ident or (group.actions and not C_SpellBook.IsSpellKnown(ident)) then
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
            local ident, ranks = REMIND.ForeverGroupCastSpell(group, spellId)
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
                local current, known, at = REMIND.ForeverGroupCastSpell(group, spellId)
                if not current then
                    return
                end
                local nextRank = at + (delta > 0 and 1 or -1)
                local nextID = known[nextRank]
                if not nextID or (group.actions and not C_SpellBook.IsSpellKnown(nextID)) then
                    return
                end
                local _, rank = REMIND.ForeverPickerSpellData(nextID, true)
                if nextRank < #known and not rank then
                    return
                end
                local selected = btn._tooltipSpell == current
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
    REMIND.HideIconTooltip(btn)
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
    local previousStyle = btn.menuMixin
    btn.menuMixin = iconPickerStyle
    local dropMenu = MenuUtil.CreateContextMenu(btn, function(_, root)
        root:AddMenuReleasedCallback(function()
            REMIND.ValidateOpenPicker = nil
        end)
        local columns = math.min(#ids, upper(1, floor((UIParent:GetWidth() - 32) / 42)))
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
                local glyph = widget:AttachTexture()
                glyph:SetDrawLayer("ARTWORK", 1)
                glyph:SetSize(34, 34)
                glyph:SetPoint("CENTER")
                glyph:SetTexture(Tex(spellId) or 134400)
                return 38, 38
            end)
            btnFrame:SetTooltip(function(tooltip, description)
                local ownerFrame = tooltip:GetOwner()
                tooltip:SetOwner(ownerFrame, "ANCHOR_NONE")
                tooltip:ClearAllPoints()
                tooltip:SetPoint("BOTTOMLEFT", ownerFrame, "TOPRIGHT", 4, 4)
                local spellId = REMIND.ForeverGroupCastSpell(group, description:GetData())
                if spellId then
                    tooltip:SetSpellByID(spellId)
                end
            end)
            AddRankControl(btnFrame, ident)
        end
    end)
    btn.menuMixin = previousStyle
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

    ApplySetup = function(btn, m)
        local modeName = m.mode
        if modeName == "spell" then
            SetIconSpell(btn, m.spellID, m.texture or Tex(m.spellID), m.label)
            if m.unit and not InCombat() then
                btn:SetAttribute("unit1", m.unit)
            end
        elseif modeName == "item" then
            SetIconItem(btn, m.itemID, m.texture, m.label)
        elseif modeName == "macro" then
            SetIconMacro(btn, m.macro, m.texture or (m.spellID and Tex(m.spellID)), m.spellID)
            btn._tooltipItem = m.tooltipItem
        else -- "texture"
            SetIconTexture(btn, m.texture, m.label)
            if m.spellID then
                btn._tooltipSpell = m.spellID
            end
            if m.tooltipItem then
                btn._tooltipItem = m.tooltipItem
            end
        end
        btn._text:SetText(m.label or "")
        btn._icon:SetDesaturated(m.desaturated or false)
        btn._tooltipLabel = m.label or nil
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
