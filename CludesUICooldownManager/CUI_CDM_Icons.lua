if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_Icons.lua
--
--  Icon shapes, the fake-active mirror, threshold and charge text and
--  RefreshCDMIconAppearance.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local Inner = ns._internals
-- The main file or an earlier CDM file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local CDM_SHAPES, FC, _ecmeFC, _getFD = Inner.CDM_SHAPES, Inner.FC, Inner._ecmeFC, Inner._getFD
local IconShownAlpha, ShowProcGlow = Inner.IconShownAlpha, Inner.ShowProcGlow
local StopNativeGlow, barDataByKey = Inner.StopNativeGlow, Inner.barDataByKey
local cdmBarIcons, GetCDMFont, SetBlizzCDMFont = Inner.cdmBarIcons, Inner.GetCDMFont, Inner.SetBlizzCDMFont

local ApplyShapeToCDMIcon

-- The options page pool's table (CludesUI_PixelPerfect.lua makes it; the
-- options addon fills it in place): read through this file local, never the
-- public slot, so nothing written to that slot later reaches the live icons.
local POOL = CludesUI._Pool

local _inCombat = false
Inner.inCombatSetters[#Inner.inCombatSetters + 1] = function(val)
    _inCombat = val
end

-------------------------------------------------------------------------------
--  Apply custom shape to a CDM icon
-------------------------------------------------------------------------------
ApplyShapeToCDMIcon = function(glyph, shape, barInfo, ssb)
    if not glyph then
        return
    end
    local fd = _getFD(glyph)
    local texture = fd and fd.tex or glyph._tex
    local cd = fd and fd.cooldown or glyph._cooldown
    local backdrop = fd and fd.bg or glyph._bg
    local zoom = barInfo.iconZoom or 0.08
    local borderSz = barInfo.borderSize or 1
    local brdR = barInfo.borderR or 0
    local brdG = barInfo.borderG or 0
    local brdB = barInfo.borderB or 0
    local brdA = barInfo.borderA or 1
    if barInfo.borderClassColor then
        local cc = ns._playerClass and RAID_CLASS_COLORS[ns._playerClass]
        if cc then
            brdR, brdG, brdB = cc.r, cc.g, cc.b
        end
    end
    -- Per-icon Border override (buff-family bars): size + color only, NEVER style. ssb is the
    -- resolved per-icon settings from RefreshCDMIconAppearance; nil for cd/utility bars and
    -- uncustomized icons, so this no-ops unless a buff icon has a per-icon border. Feeds both the square (ApplyBorderStyle) and shaped (shapeBorder) paths below.
    if ssb then
        if ssb.borderSize ~= nil then
            borderSz = ssb.borderSize
        end
        if ssb.borderR ~= nil then
            brdR = ssb.borderR
        end
        if ssb.borderG ~= nil then
            brdG = ssb.borderG
        end
        if ssb.borderB ~= nil then
            brdB = ssb.borderB
        end
    end

    local ifc = FC(glyph)
    -- Stock styles: the style's ring replaces every CUI shape and the square
    -- border, and the icon shows its full art (no zoom) exactly as the viewer
    -- draws it (rounded by the viewer mask under Blizzard Style, square under
    -- Classic WoW UI).
    local blizzArt = ns.CdmBlizzIcons()
    if blizzArt then
        shape = "none"
        zoom = 0
    end
    if shape == "none" or shape == "cropped" or not shape then
        -- Remove shape mask if previously applied
        if ifc.shapeMask then
            local mask = ifc.shapeMask
            if texture then
                pcall(texture.RemoveMaskTexture, texture, mask)
            end
            if backdrop then
                pcall(backdrop.RemoveMaskTexture, backdrop, mask)
            end
            if cd then
                pcall(cd.RemoveMaskTexture, cd, mask)
            end
            mask:SetTexture(nil)
            mask:ClearAllPoints()
            mask:SetSize(0.001, 0.001)
            mask:Hide()
        end
        if ifc.shapeBorder then
            ifc.shapeBorder:Hide()
        end
        ifc.shapeApplied = nil
        ifc.shapeName = nil

        -- Restore square borders (PP or textured via ApplyBorderStyle). The border lives on
        -- fd.borderFrame (child of icon) so Blizzard's secure frames are never tainted; PP.GetBorders(icon) is the fallback for CDM-owned frames that skip DecorateFrame's child wrapper.
        local bdrTarget = (fd and fd.borderFrame) or glyph
        if blizzArt then
            -- Blizzard Style draws no CUI border (the ring overlay is the frame).
        elseif fd and fd.borderFrame or CludesUI.PP.GetBorders(glyph) then
            local texKey = barInfo.borderTexture or "solid"
            -- Exact size (borderSizePx) belongs to the bar's own step: a per-icon
            -- override that differs from it fails the step compare and stays legacy,
            -- one equal to it takes the bar's px like the other two paint paths.
            local edgePx = CludesUI.BorderPx(barInfo.borderSizePx, borderSz, texKey)
            -- "Show Behind": set the border frame's level BEFORE styling so the
            -- textured backdrop inherits it. +13 = in front (+14 for the Pixels styles), level-1 = behind.
            if fd and fd.borderFrame then
                fd.borderFrame:SetFrameLevel(
                    barInfo.borderBehind and math.max(0, glyph:GetFrameLevel() - 1)
                        or (glyph:GetFrameLevel() + (CludesUI._pixelArtBorders[texKey] and 14 or 13))
                )
            end
            CludesUI.ApplyBorderStyle(
                bdrTarget,
                borderSz,
                brdR,
                brdG,
                brdB,
                brdA,
                texKey,
                barInfo.borderTextureOffset,
                barInfo.borderTextureOffsetY,
                barInfo.borderTextureShiftX,
                barInfo.borderTextureShiftY,
                "cdm",
                barInfo.borderThickness or "thin",
                true,
                edgePx
            )
        end

        -- Restore icon texture, filling the entire frame: PP.CreateBorder renders the border on top, so no inset is needed.
        if texture then
            texture:ClearAllPoints()
            texture:SetAllPoints(glyph)
            local extraCrop = 0
            if ifc.matchExpanded then
                local baseW = barInfo.iconSize or 36
                extraCrop = (1 - 2 * zoom) / (2 * (baseW + 1))
            end
            if blizzArt then
                -- Full art, as the viewer draws it (rounded by the viewer mask
                -- under Blizzard Style, square under Classic WoW UI).
                if texture.SetSnapToPixelGrid then
                    texture:SetSnapToPixelGrid(true)
                end
                texture:SetTexCoord(0, 1, 0, 1)
            elseif shape == "cropped" then
                -- Cropped applies a heavy vertical TexCoord crop. With default pixel/texel
                -- snapping the cropped image edge can round to a different physical pixel than
                -- the unsnapped cooldown swipe (1px swipe/icon split at some effective scales), so snapping is disabled to render the exact rect. No size change.
                if texture.SetSnapToPixelGrid then
                    texture:SetSnapToPixelGrid(false)
                end
                if texture.SetTexelSnappingBias then
                    texture:SetTexelSnappingBias(0)
                end
                local trim = ns.CdmCropTrim(barInfo)
                texture:SetTexCoord(zoom, 1 - zoom, zoom + trim + extraCrop, 1 - zoom - trim - extraCrop)
            else
                -- Restore default grid snapping so an icon switched away from cropped stays crisp.
                if texture.SetSnapToPixelGrid then
                    texture:SetSnapToPixelGrid(true)
                end
                texture:SetTexCoord(zoom, 1 - zoom, zoom + extraCrop, 1 - zoom - extraCrop)
            end
        end

        -- Restore cooldown: full frame so the swipe covers the entire icon
        if cd then
            cd:ClearAllPoints()
            cd:SetAllPoints(glyph)
            pcall(cd.SetSwipeTexture, cd, ns.CdmSwipeFile())
            if cd.SetUseCircularEdge then
                pcall(cd.SetUseCircularEdge, cd, false)
            end
        end

        -- Restore background
        if backdrop then
            backdrop:ClearAllPoints()
            backdrop:SetAllPoints()
        end
        return
    end

    -- Custom shape
    local maskTex = CDM_SHAPES.masks[shape]
    if not maskTex then
        return
    end

    if not ifc.shapeMask then
        ifc.shapeMask = glyph:CreateMaskTexture()
    end
    local mask = ifc.shapeMask
    mask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:Show()

    -- Remove existing mask refs before re-adding
    if texture then
        pcall(texture.RemoveMaskTexture, texture, mask)
    end
    if backdrop then
        pcall(backdrop.RemoveMaskTexture, backdrop, mask)
    end
    if cd then
        pcall(cd.RemoveMaskTexture, cd, mask)
    end
    if glyph.OutOfRange then
        pcall(glyph.OutOfRange.RemoveMaskTexture, glyph.OutOfRange, mask)
    end

    -- Apply mask to icon texture, background, and OutOfRange overlay
    if texture then
        texture:AddMaskTexture(mask)
    end
    if backdrop then
        backdrop:AddMaskTexture(mask)
    end
    if glyph.OutOfRange then
        local oor = glyph.OutOfRange
        pcall(oor.RemoveMaskTexture, oor, mask)
        pcall(oor.AddMaskTexture, oor, mask)
    end

    -- Expand icon beyond frame for shape
    local shapeOffset = CDM_SHAPES.iconExpandOffsets[shape] or 0
    local shapeDefault = CDM_SHAPES.zoomDefaults[shape] or 0.06
    local iconExp = CDM_SHAPES.iconExpand + shapeOffset + ((zoom - shapeDefault) * 200)
    if iconExp < 0 then
        iconExp = 0
    end
    local halfIE = iconExp / 2
    if texture then
        texture:ClearAllPoints()
        CludesUI.PP.Point(texture, "TOPLEFT", glyph, "TOPLEFT", -halfIE, halfIE)
        CludesUI.PP.Point(texture, "BOTTOMRIGHT", glyph, "BOTTOMRIGHT", halfIE, -halfIE)
    end

    -- Mask position (inset for border)
    mask:ClearAllPoints()
    if borderSz >= 1 then
        CludesUI.PP.Point(mask, "TOPLEFT", glyph, "TOPLEFT", 1, -1)
        CludesUI.PP.Point(mask, "BOTTOMRIGHT", glyph, "BOTTOMRIGHT", -1, 1)
    else
        mask:SetAllPoints(glyph)
    end

    -- Expand texcoords for shape
    local insetPx = CDM_SHAPES.insets[shape] or 17
    local visRatio = (128 - 2 * insetPx) / 128
    local expand = ((1 / visRatio) - 1) * 0.5
    if texture then
        texture:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand)
    end

    -- Hide square borders (both PP and textured)
    local bdrTarget2 = (fd and fd.borderFrame) or glyph
    if fd and fd.borderFrame or CludesUI.PP.GetBorders(glyph) then
        CludesUI.PP.HideBorder(bdrTarget2)
        if CludesUI._bdBorderData then
            local bdFrame = CludesUI._bdBorderData[bdrTarget2]
            if bdFrame then
                bdFrame:Hide()
            end
        end
    end

    -- Shape border texture (on a dedicated frame above the cooldown swipe).
    -- On an options preview slot (an options page pool host) the frame is
    -- pooled with the slot; on a live icon this is the plain CreateFrame.
    if not ifc.shapeBorderFrame then
        local sbf = POOL.CreateFrame("Frame", nil, glyph)
        sbf:SetAllPoints(glyph)
        sbf:SetFrameLevel(glyph:GetFrameLevel() + 2)
        ifc.shapeBorderFrame = sbf
    end
    ifc.shapeBorderFrame:SetFrameLevel(glyph:GetFrameLevel() + 2)
    if not ifc.shapeBorder then
        ifc.shapeBorder = ifc.shapeBorderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    end
    local borderTex = ifc.shapeBorder
    borderTex:ClearAllPoints()
    borderTex:SetAllPoints(glyph)
    if borderSz > 0 and CDM_SHAPES.borders[shape] then
        borderTex:SetTexture(CDM_SHAPES.borders[shape])
        borderTex:SetVertexColor(brdR, brdG, brdB, brdA)
        borderTex:SetSnapToPixelGrid(false)
        borderTex:SetTexelSnappingBias(0)
        borderTex:Show()
    else
        borderTex:Hide()
    end

    -- Apply mask to cooldown so swipe follows shape
    if cd then
        cd:ClearAllPoints()
        cd:SetAllPoints(glyph)
        pcall(cd.AddMaskTexture, cd, mask)
        if cd.SetSwipeTexture then
            pcall(cd.SetSwipeTexture, cd, maskTex)
        end
        local useCircular = (shape ~= "square" and shape ~= "csquare")
        if cd.SetUseCircularEdge then
            pcall(cd.SetUseCircularEdge, cd, useCircular)
        end
        local edgeScale = CDM_SHAPES.edgeScales[shape] or 0.60
        if cd.SetEdgeScale then
            pcall(cd.SetEdgeScale, cd, edgeScale)
        end
    end

    -- Restore background to full icon
    if backdrop then
        backdrop:ClearAllPoints()
        backdrop:SetAllPoints()
    end

    ifc.shapeApplied = true
    ifc.shapeName = shape
end
ns.ApplyShapeToCDMIcon = ApplyShapeToCDMIcon

-------------------------------------------------------------------------------
--  Mirror an icon's custom shape onto a fake-active overlay's own icon + swipe
-------------------------------------------------------------------------------
-- The CDM "fake active" engine (CludesUICdmFakeActive.lua) draws its own saturated icon +
-- swipe over a CDM icon during a custom active window. The overlay MUST copy the underlying
-- icon's custom shape or a square icon/swipe is drawn over the shaped icon and the mask looks
-- broken. Reuses the underlying shapeMask: masking is screen-space and the overlay covers the same region, so one mask serves both. A none/cropped shape clears any mask we added and restores a plain square swipe.
function ns.ApplyShapeToOverlay(glyph, oIcon, oCd, barInfo)
    if not glyph then
        return
    end
    local ifc = FC(glyph)
    local mask = ifc.shapeMask
    local shape = ifc.shapeApplied and ifc.shapeName or nil

    -- Drop mask refs we added before (the shape may have changed / cleared).
    if mask then
        if oIcon then
            pcall(oIcon.RemoveMaskTexture, oIcon, mask)
        end
        if oCd then
            pcall(oCd.RemoveMaskTexture, oCd, mask)
        end
    end

    local maskTex = shape and CDM_SHAPES.masks[shape]
    if not shape or shape == "none" or shape == "cropped" or not mask or not maskTex then
        -- Square overlay. IconTexture already copied the underlying texcoords.
        if oIcon then
            oIcon:ClearAllPoints()
            oIcon:SetAllPoints(oIcon:GetParent())
        end
        if oCd then
            pcall(oCd.SetSwipeTexture, oCd, "Interface\\AddOns\\CludesUI\\media\\white-square.png")
            if oCd.SetUseCircularEdge then
                pcall(oCd.SetUseCircularEdge, oCd, false)
            end
        end
        return
    end

    local zoom = (barInfo and barInfo.iconZoom) or 0.08

    -- Match the underlying tex geometry: point-expand + texcoord-expand.
    local shapeOffset = CDM_SHAPES.iconExpandOffsets[shape] or 0
    local shapeDefault = CDM_SHAPES.zoomDefaults[shape] or 0.06
    local iconExp = CDM_SHAPES.iconExpand + shapeOffset + ((zoom - shapeDefault) * 200)
    if iconExp < 0 then
        iconExp = 0
    end
    local halfIE = iconExp / 2
    if oIcon then
        oIcon:ClearAllPoints()
        CludesUI.PP.Point(oIcon, "TOPLEFT", glyph, "TOPLEFT", -halfIE, halfIE)
        CludesUI.PP.Point(oIcon, "BOTTOMRIGHT", glyph, "BOTTOMRIGHT", halfIE, -halfIE)
        local insetPx = CDM_SHAPES.insets[shape] or 17
        local visRatio = (128 - 2 * insetPx) / 128
        local expand = ((1 / visRatio) - 1) * 0.5
        oIcon:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand)
        oIcon:AddMaskTexture(mask)
    end
    if oCd then
        oCd:ClearAllPoints()
        oCd:SetAllPoints(glyph)
        pcall(oCd.AddMaskTexture, oCd, mask)
        if oCd.SetSwipeTexture then
            pcall(oCd.SetSwipeTexture, oCd, maskTex)
        end
        local useCircular = (shape ~= "square" and shape ~= "csquare")
        if oCd.SetUseCircularEdge then
            pcall(oCd.SetUseCircularEdge, oCd, useCircular)
        end
        local edgeScale = CDM_SHAPES.edgeScales[shape] or 0.60
        if oCd.SetEdgeScale then
            pcall(oCd.SetEdgeScale, oCd, edgeScale)
        end
    end
end

-------------------------------------------------------------------------------
--  Style a fake-active overlay's own countdown number to match Duration Text
-------------------------------------------------------------------------------
local COOLDOWN_TEXT_POINTS = {
    center = { "CENTER", "CENTER", "CENTER" },
    top = { "BOTTOM", "TOP", "CENTER" },
    bottom = { "TOP", "BOTTOM", "CENTER" },
    left = { "RIGHT", "LEFT", "RIGHT" },
    right = { "LEFT", "RIGHT", "LEFT" },
}

function ns.AnchorCooldownText(textValue, ownerFrame, position, posX, posY)
    local points = COOLDOWN_TEXT_POINTS[position] or COOLDOWN_TEXT_POINTS.center
    textValue:ClearAllPoints()
    textValue:SetPoint(points[1], ownerFrame, points[2], posX or 0, posY or 0)
    textValue:SetJustifyH(points[3])
end

-- Does this bar show Duration Text? The options row treats the key as ON
-- unless it is explicitly false, so every renderer must too: read bare, a bar
-- whose key was never written (imported profile, RPT sync, a strip the login
-- merge did not refill) shows the toggle ON and draws no numbers.
function ns.CdmDurationTextOn(edge)
    return edge ~= nil and edge.showCooldownText ~= false
end

-- Stack/charge/item-count text anchor. Bottom-anchored positions keep the
-- historical +2 nudge so existing bars stay pixel-identical. Shared with the
-- custom-aura renderer (CludesUICdmHooks) so both land on the same anchor.
function ns.CdmStackAnchorPoint(position, posY)
    posY = posY or 0
    if position == "bottomleft" then
        return "BOTTOMLEFT", posY + 2
    end
    if position == "bottom" then
        return "BOTTOM", posY + 2
    end
    if position == "topright" then
        return "TOPRIGHT", posY
    end
    if position == "top" then
        return "TOP", posY
    end
    if position == "topleft" then
        return "TOPLEFT", posY
    end
    if position == "center" then
        return "CENTER", posY
    end
    if position == "left" then
        return "LEFT", posY
    end
    if position == "right" then
        return "RIGHT", posY
    end
    return "BOTTOMRIGHT", posY + 2
end

-- The overlay (CludesUICdmFakeActive.lua) runs its own Cooldown widget whose
-- number would otherwise use Blizzard's default font. Mirrors the Duration Text
-- styling the real icon gets in RefreshCDMIconAppearance: font, size
-- (scale-compensated), colour, position, offset, show/hide. ssb is the resolved
-- per-icon settings, falling back to the bar's (nil is fine). Call AFTER
-- SetCooldown so Blizzard's countdown FontString exists.
function ns.StyleOverlayCooldownText(oCd, barInfo, ssb, iconScale)
    if not oCd then
        return
    end
    iconScale = iconScale or 1
    if iconScale < 0.01 then
        iconScale = 1
    end
    local fontScale = 1 / iconScale
    local showCD = ns.CdmDurationTextOn(barInfo)
    if ssb and ssb.showCooldownText ~= nil then
        showCD = ssb.showCooldownText
    end
    oCd:SetHideCountdownNumbers(not showCD)
    if not showCD then
        return
    end
    local cdFont = GetCDMFont()
    local cdSize = ((ssb and ssb.cooldownFontSize) or (barInfo and barInfo.cooldownFontSize) or 12)
        * fontScale
    local cdR = (ssb and ssb.cooldownTextR) or (barInfo and barInfo.cooldownTextR) or 1
    local cdG = (ssb and ssb.cooldownTextG) or (barInfo and barInfo.cooldownTextG) or 1
    local cdB = (ssb and ssb.cooldownTextB) or (barInfo and barInfo.cooldownTextB) or 1
    local cdPosition = (ssb and ssb.cooldownTextPosition)
        or (barInfo and barInfo.cooldownTextPosition)
        or "center"
    local cdX = (ssb and ssb.cooldownTextX) or (barInfo and barInfo.cooldownTextX) or 0
    local cdY = (ssb and ssb.cooldownTextY) or (barInfo and barInfo.cooldownTextY) or 0
    for _, region in pairs({ oCd:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            CludesUI.ApplyIconTextFont(region, cdFont, cdSize, "cdm")
            region:SetTextColor(cdR, cdG, cdB)
            ns.AnchorCooldownText(region, oCd, cdPosition, cdX, cdY)
        end
    end
end

-------------------------------------------------------------------------------
--  Per-spell Threshold Text (engine countdown formatters)
--
--  "Threshold Seconds" arms the feature per spell; below that many seconds
--  remaining the countdown can show one decimal ("2.7") and/or change color.
--  Rendered by a NumericRuleFormatter attached to the icon's Cooldown widget via
--  SetCountdownFormatter: the ENGINE formats the number (no OnUpdate, no
--  per-tick Lua), it covers whatever the widget displays (cooldown, recharge,
--  aura duration, fake-active window), and it evaluates engine-side so SECRET
--  durations format fine. The color change rides IN the format string (color
--  escape wrap), so no text-color swapping at the threshold edge. Formatters are
--  immutable per config and shared: one instance per distinct (seconds,
--  decimals, color) tuple, attached to any number of cooldowns.
-------------------------------------------------------------------------------
do
    local formatters = {} -- [signature] = engine formatter object
    local formatterCount = 0
    local unsupported = false -- API probe failed once -> feature stays inert
    -- Which formatter a cooldown currently has attached, so the refresh pass only touches widgets
    -- it manages (the all-off case is one weak-table read). Weak keys: pooled frames drop out on their own. State lives HERE, never on the frames (many are Blizzard-owned).
    local attached = setmetatable({}, { __mode = "k" })

    local function BuildFormatter(seconds, dec, column, r, g, b)
        if
            not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding)
        then
            return nil
        end
        local Up = Enum.NumericRuleFormatRounding.Up
        local Nearest = Enum.NumericRuleFormatRounding.Nearest
        local function Wrap(fmt)
            if not column then
                return fmt
            end
            return CreateColor(r, g, b, 1):WrapTextInColorCode(fmt)
        end
        local points = {}
        if dec then
            -- One decimal below the threshold, whole seconds above it.
            points[#points + 1] = { threshold = 0, format = Wrap("%.1f"), rounding = Nearest }
        else
            -- Color-only: same whole-second text, wrapped below the threshold.
            points[#points + 1] = { threshold = 0, format = Wrap("%d"), rounding = Up, step = 1 }
        end
        points[#points + 1] = { threshold = seconds, format = "%d", rounding = Up, step = 1 }
        -- Larger units. Thresholds sit just above the unit boundary so an UP-rounded value in
        -- (59, 60] routes into the m:ss breakpoint rather than reading "60" for a moment (same for hours and days).
        points[#points + 1] = {
            threshold = 59.0001,
            format = "%d:%02d",
            rounding = Up,
            step = 1,
            components = { { div = 60 }, { mod = 60 } },
        }
        points[#points + 1] = {
            threshold = 3599.0001,
            format = "%dh",
            rounding = Up,
            step = 1,
            components = { { div = 3600 } },
        }
        points[#points + 1] = {
            threshold = 86399.0001,
            format = "%dd",
            rounding = Up,
            step = 1,
            components = { { div = 86400 } },
        }
        local f = C_StringUtil.CreateNumericRuleFormatter()
        local success = pcall(f.SetBreakpoints, f, points)
        if not success then
            return nil
        end
        return f
    end

    -- Resolve a settings block's threshold config to a shared formatter, or nil when off. ss may
    -- be a per-spell family entry (tier-chained), a customActiveStates entry, or nil. Explicit false (tier blocking) reads as off through the tonumber/== true checks.
    local function FormatterFor(ss)
        if not ss then
            return nil
        end
        local seconds = tonumber(ss.thresholdSeconds) or 0
        if seconds <= 0 then
            return nil
        end
        if seconds > 59 then
            seconds = 59
        end
        local dec = ss.thresholdDecimals == true
        local column = ss.thresholdColorEnabled == true
        if not (dec or column) then
            return nil
        end
        local r, g, b = 1, 0.2, 0.2
        if column then
            r = ss.thresholdColorR or 1
            g = ss.thresholdColorG or 0.2
            b = ss.thresholdColorB or 0.2
        end
        local sig = string.format(
            "%d|%s|%s",
            seconds,
            dec and "1" or "0",
            column and string.format("%.3f,%.3f,%.3f", r, g, b) or "0"
        )
        local f = formatters[sig]
        if f == nil and not unsupported then
            -- Live color-picker drags mint a config per tick, so cap the lookup. Attached widgets keep their instances alive; evicted configs rebuild on demand.
            if formatterCount > 64 then
                formatters = {}
                formatterCount = 0
            end
            f = BuildFormatter(seconds, dec, column, r, g, b)
            if f then
                formatters[sig] = f
                formatterCount = formatterCount + 1
            else
                unsupported = true
            end
        end
        return f
    end

    -- Attach or clear the resolved formatter on one Cooldown widget. Touches the widget only on a managed-state change, and never one it never managed.
    function ns.ApplyThresholdFormatter(cd, ss)
        if not (cd and cd.SetCountdownFormatter) then
            return
        end
        local f = FormatterFor(ss)
        if f then
            if attached[cd] ~= f then
                attached[cd] = f
                cd:SetCountdownFormatter(f)
            end
        elseif attached[cd] then
            attached[cd] = nil
            cd:SetCountdownFormatter(nil)
        end
    end

    -- Effective threshold config for a frame's spell: per-spell family store (tier-chained) first,
    -- then the preset/custom customActiveStates entry -- the same two homes Reverse Swipe reads. Returns the arming block, or nil.
    function ns.ResolveThresholdTextSettings(widget, spellRef, sd, barId)
        if not spellRef then
            return nil
        end
        local ss
        if ns.ResolveSpellSettings then
            ss = ns.ResolveSpellSettings(widget, spellRef, sd, barId)
        end
        if ss and (tonumber(ss.thresholdSeconds) or 0) > 0 then
            return ss
        end
        if ns.GetEffectiveCustomActiveState then
            local cas = ns.GetEffectiveCustomActiveState(spellRef)
            if cas and (tonumber(cas.thresholdSeconds) or 0) > 0 then
                return cas
            end
        end
        return nil
    end
end

-- Styles the custom-spell "Show Charges" count text (created lazily by the CdmHooks ticker) to
-- match the bar's native stack/charge text: font, size, color, anchor position and X/Y offset.
-- Called at creation and from every RefreshCDMIconAppearance pass so option changes apply live. With no bar data the defaults resolve to size 11, bottom-right, +2 nudge.
function ns.StyleCustomChargeText(glyph, barId)
    local fontStr = glyph and glyph._castCountText
    if not fontStr then
        return
    end
    local barInfo = (barId and barDataByKey[barId]) or {}
    -- Fonts render at the frame's native scale; compensate like the main pass.
    local iconScale = glyph:GetScale() or 1
    if iconScale < 0.01 then
        iconScale = 1
    end
    local scSize = (barInfo.stackCountSize or 11) / iconScale
    local scX = (barInfo.stackCountX or 0) / iconScale
    local scY = (barInfo.stackCountY or 0) / iconScale
    local scPoint = barInfo.stackCountPosition or "bottomright"
    if scPoint == "bottomleft" then
        scPoint = "BOTTOMLEFT"
        scY = scY + 2
    elseif scPoint == "bottom" then
        scPoint = "BOTTOM"
        scY = scY + 2
    elseif scPoint == "topright" then
        scPoint = "TOPRIGHT"
    elseif scPoint == "top" then
        scPoint = "TOP"
    elseif scPoint == "topleft" then
        scPoint = "TOPLEFT"
    elseif scPoint == "center" then
        scPoint = "CENTER"
    elseif scPoint == "left" then
        scPoint = "LEFT"
    elseif scPoint == "right" then
        scPoint = "RIGHT"
    else
        scPoint = "BOTTOMRIGHT"
        scY = scY + 2
    end
    SetBlizzCDMFont(
        fontStr,
        GetCDMFont(),
        scSize,
        barInfo.stackCountR or 1,
        barInfo.stackCountG or 1,
        barInfo.stackCountB or 1
    )
    -- Parent onto the text overlay so it renders above the border.
    local fd = _getFD(glyph)
    local txOverlay = (fd and fd.textOverlay) or glyph._textOverlay
    if txOverlay then
        fontStr:SetParent(txOverlay)
    end
    fontStr:ClearAllPoints()
    fontStr:SetPoint(scPoint, txOverlay or glyph, scPoint, scX, scY)
end

-- Refresh visual properties of existing icons (called when settings change)
local function RefreshCDMIconAppearance(barId)
    -- Custom auras render in their own engine container, so their style is
    -- re-applied here rather than in the icon loop -- and before the early-outs
    -- below, since a bar can hold custom auras and no icons of its own.
    if ns.RefreshAuraCustomStyle then
        ns.RefreshAuraCustomStyle(barId)
    end
    -- Our aura icons' slots wear the same look (CUI_CDM_AuraIcons.lua).
    if ns.CDM_AuraIconsRestyle then
        ns.CDM_AuraIconsRestyle(barId)
    end
    local icons = cdmBarIcons[barId]
    if not icons then
        return
    end

    local barInfo = barDataByKey[barId]
    if not barInfo then
        return
    end

    local borderSize = barInfo.borderSize or 1
    local zoom = barInfo.iconZoom or 0.08
    -- Blizzard Style: full art, no CUI border/background; the ring overlay and
    -- rounded mask are (re)applied after the shape pass below.
    local blizzArt = ns.CdmBlizzIcons()
    if blizzArt then
        zoom = 0
    end

    for _, glyph in ipairs(icons) do
        -- Empty Slot: pure grid spacer, deliberately never decorated (see
        -- DecorateFrame) -- skip every bar-wide/per-icon style and cd-state pass
        -- so a bar's Glow (CD Ready) or other "apply to bar" effect can never
        -- attach to it (its bogus marker id never carries a real cooldown, so
        -- it would otherwise resolve as permanently ready and glow forever).
        if not glyph._isEmptySlotFrame then
            local fd = _getFD(glyph)
            local texture = fd and fd.tex or glyph._tex
            local cd = fd and fd.cooldown or glyph._cooldown
            local backdrop = fd and fd.bg or glyph._bg
            local glowOv = fd and fd.glowOverlay or glyph._glowOverlay
            local kbText = fd and fd.keybindText or glyph._keybindText
            local txOverlay = fd and fd.textOverlay or glyph._textOverlay
            -- Scale compensation: fonts render at the frame's native scale, so multiply sizes by 1/scale to match the visual icon size.
            local iconScale = glyph:GetScale() or 1
            if iconScale < 0.01 then
                iconScale = 1
            end
            local fontScale = 1 / iconScale
            -- Per-icon override settings (buff-family bars only). Resolved once and reused for Buff
            -- Glow + Duration Text + Charge/Stack below; nil = inherit the bar's value. Variant-aware:
            -- a setting stored under any spell in the icon's family (base/talent-override) resolves here -- options keys off the live/canonical id, which may differ from fc.spellID.
            local ssb
            -- Canonical id for buff-family icons, hoisted so the Threshold Text block below can
            -- reuse it instead of re-walking GetCanonicalSpellIDForFrame a second time this pass.
            local sidb
            local isBuffFamilyBar = (barInfo.barType == "buffs" or barId == "buffs")
            -- Login/refresh coverage for Max Stacks Glow: a charge spell at max never fires the swipe hook, so register here too. Gated on the feature flag so non-users skip the call entirely.
            if ns._cdmAnyMaxStacksGlow and not isBuffFamilyBar and ns.WatchMaxStacksIfEnabled then
                ns.WatchMaxStacksIfEnabled(glyph)
            end
            -- Same for "Hide CD Text (Charges)": a charge spell at max shows no recharge text and never fires the swipe hook. Same feature-flag gate.
            if ns._cdmAnyChargeHideCdText and not isBuffFamilyBar and ns.WatchChargeCdTextIfEnabled then
                ns.WatchChargeCdTextIfEnabled(glyph)
            end
            -- "Hide Text at 0 Stacks" (bar-level): enroll/refresh on the same login + settings-change
            -- pass. Gated on the bar's key plus a next() probe so turning it OFF still reaches the unwatch/restore path; both empty = skipped entirely.
            if
                not isBuffFamilyBar
                and ns.WatchZeroChargeTextIfEnabled
                and (
                    barInfo.hideZeroChargeText
                    or ns._cdmAnyHideChargeText
                    or next(ns._zeroChargeTextWatch or {}) ~= nil
                )
            then
                ns.WatchZeroChargeTextIfEnabled(glyph)
            end
            -- Re-assert Hide Recharge Edge/Hide Swipe on charge icons so a toggle updates a
            -- currently-recharging spell immediately instead of waiting for the next recharge to fire the reactive SetDrawEdge/SetDrawSwipe hooks. Gated + self-skips non-charge frames = 0 cost unless in use.
            if ns._cdmAnyChargeStyle and not isBuffFamilyBar and ns.ReapplyChargeStyle then
                ns.ReapplyChargeStyle(glyph)
            end
            -- "Audio Effect on CD Ready": register cd/utility icons with the sound onto the event-driven
            -- watcher (SPELL_UPDATE_COOLDOWN + SPELL_UPDATE_CHARGES; charge and non-charge both handled there). Icons without the sound self-skip inside.
            if ns._cdmAnyCdReadySound and not isBuffFamilyBar and ns.WatchCdReadySoundIfEnabled then
                ns.WatchCdReadySoundIfEnabled(glyph)
            end
            -- Buff per-spell settings resolve for any BUFF FRAME, not just buff-family bars: a hosted
            -- buff (real Blizzard buff frame reparented onto a CD/util bar, flagged fd._isBuffViewerFrame)
            -- and its inactive placeholder need the same resolution so their Buff Glow/Duration Text/Charge-Stack/Border/Desaturate match the active frame.
            if isBuffFamilyBar or (fd and fd._isBuffViewerFrame) or glyph._isPlaceholderFrame then
                -- Per-icon Audio on Buff Gain/Loss: attach the gain+loss hooks once, only when the feature is in use anywhere.
                if ns._cdmAnyBuffSound and ns.EnsureBuffSoundHook then
                    ns.EnsureBuffSoundHook(glyph)
                end
                local fcb = _ecmeFC[glyph]
                -- Resolve by the DISPLAYED spell first (GetCanonicalSpellIDForFrame, the id the options
                -- menu writes settings under) rather than fc.spellID (the cooldownInfo base). For buffs
                -- whose base is a generic spec spell shared across icons (Consecration's standing-in
                -- aura -> Prot Paladin 137028), keying off the base misses the real buff AND lets one
                -- icon's setting shadow another's. canon as primary makes settings[canon] the fast path. Own placeholder/custom frames have no live spell -> fc.spellID.
                sidb = (ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(glyph))
                    or (fcb and fcb.spellID)
                if sidb then
                    local sdb = ns.GetBarSpellData(barId)
                    -- Shared resolver: matches the key against the frame's full identity set (canon first, then resolvedSid/baseSpellID).
                    ssb = ns.ResolveSpellSettings and ns.ResolveSpellSettings(glyph, sidb, sdb, barId)
                end
                -- Stash the effective Buff Glow on fd so the BuffTicker hot path reads it without a
                -- per-tick lookup. Only restart the live glow when the effective value actually changed (no flicker on no-op rebuilds).
                local nT = ssb and ssb.buffGlow -- nil = inherit, number = override (0 = None)
                -- A false-block (per-spell "Off", or Exclude this spec/bar apply of an Off value) is
                -- render-equivalent to nil: treat it as inherit, never as a value. Without this fd._bgT would be `false` and the BuffTicker's `effGlowType > 0` compares a boolean with a number and errors.
                if nT == false then
                    nT = nil
                end
                local nColor = ssb and ssb.buffGlowColor -- nil / "class" / "custom"
                local nR, nG, nB
                if nColor == "custom" and ssb then
                    nR, nG, nB = ssb.buffGlowColorR, ssb.buffGlowColorG, ssb.buffGlowColorB
                end
                -- Glow at Stacks: only with the per-spell toggle ON and a sane
                -- comparison. Own custom frames expose no native applications
                -- count, so they keep the normal presence glow.
                local nThreshold, nOperator
                if ssb and ssb.buffGlowStackEnabled then
                    -- Default 2 when the toggle is on before the input was ever
                    -- touched (matches the input's displayed default). A missing
                    -- operator keeps the original at-least behaviour.
                    nThreshold = tonumber(ssb.buffGlowStackThreshold) or 2
                    if nThreshold < 1 then
                        nThreshold = nil
                    end
                    nOperator = ssb.buffGlowStackOperator or "gte"
                end
                if glyph._isCustomBuffFrame or not ns.StackGlow_Configure then
                    nThreshold, nOperator = nil, nil
                end
                -- Glow When Visible: the BuffTicker lights the glow whenever the icon is shown
                -- (a Show When Missing placeholder included); Glow at Stacks wins over it.
                local nVisible = (ssb and ssb.glowWhenVisible) or nil
                if fd then
                    if
                        fd._bgT ~= nT
                        or fd._bgColor ~= nColor
                        or fd._bgR ~= nR
                        or fd._bgG ~= nG
                        or fd._bgB ~= nB
                        or fd._bgThreshold ~= nThreshold
                        or fd._bgStackOperator ~= nOperator
                        or fd._bgVisible ~= nVisible
                    then
                        fd._bgT = nT
                        fd._bgColor = nColor
                        fd._bgR = nR
                        fd._bgG = nG
                        fd._bgB = nB
                        fd._bgThreshold = nThreshold
                        fd._bgStackOperator = nOperator
                        fd._bgVisible = nVisible
                        if fd.buffGlowActive and fd.buffGlowOverlay then
                            StopNativeGlow(fd.buffGlowOverlay)
                            fd.buffGlowActive = false
                        end
                    end
                    -- Per-icon Desaturate Inactive override, read by the BuffTicker.
                    fd._desatOverride = (ssb and ssb.desatInactive) or nil

                    if nThreshold then
                        -- Style: the spell's effective Buff Glow (per-spell
                        -- override falling back to the bar's), with None and
                        -- Blizzard Default falling back to Modern WoW Glow so the
                        -- threshold always has a maskable glow to drive.
                        local sgStyle = nT
                        if sgStyle == nil then
                            sgStyle = barInfo.buffGlowType
                        end
                        sgStyle = tonumber(sgStyle) or 0
                        if sgStyle <= 0 then
                            sgStyle = 6
                        end -- Modern WoW Glow
                        local sgMode = nColor or barInfo.buffGlowMode
                        local sgR, sgG, sgB
                        if nColor == "custom" then
                            sgR, sgG, sgB = nR, nG, nB
                        elseif sgMode == "class" then
                            local cc = CludesUI.GetClassColor(CludesUI._playerClass)
                            if cc then
                                sgR, sgG, sgB = cc.r, cc.g, cc.b
                            end
                        elseif sgMode == "custom" then
                            sgR, sgG, sgB = barInfo.buffGlowR, barInfo.buffGlowG, barInfo.buffGlowB
                        end
                        ns.StackGlow_Configure(glyph, nThreshold, nOperator, sgStyle, sgR, sgG, sgB, barInfo)
                    elseif fd.stackGlow then
                        ns.StackGlow_Configure(glyph)
                    end
                end
            elseif fd and fd.stackGlow and ns.StackGlow_Configure then
                -- Blizzard viewer frames are pooled across cooldown and buff
                -- families: retire a controller when its frame goes non-buff.
                ns.StackGlow_Configure(glyph)
            end
            -- Update texture -- fill the entire frame. The border renders on top via PP.CreateBorder so no inset is needed.
            if texture then
                texture:ClearAllPoints()
                texture:SetAllPoints(glyph)
                texture:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
            end
            -- Update cooldown (full frame so swipe covers the entire icon). The swipe and the countdown
            -- number both live on the Cooldown widget, so raise the whole widget ABOVE our border
            -- (icon+13) or the border draws over the number (most visible with edge-offset text);
            -- anchoring the number to cd (below) keeps the X/Y offset working. Side effect: the dark swipe lightly tints the thin border while active.
            -- The Pixels styles swap the two (cd +13, border +14): a square swipe over their line squares off its rounded corners.
            if cd then
                cd:ClearAllPoints()
                cd:SetAllPoints(glyph)
                -- Above the border (icon+13; below it at +13 under Pixels); still below glow (icon+16) / text (icon+23).
                pcall(
                    cd.SetFrameLevel,
                    cd,
                    glyph:GetFrameLevel() + (CludesUI._pixelArtBorders[barInfo.borderTexture] and 13 or 14)
                )
                -- Per-icon Duration Text override (ssb) falls back to the bar's values. Only Show
                -- Numbers no longer forces this on: hiding the duration (bar toggle or per-icon) under it leaves just the stack count.
                local showCD = ns.CdmDurationTextOn(barInfo)
                if ssb and ssb.showCooldownText ~= nil then
                    showCD = ssb.showCooldownText
                end
                cd:SetSwipeColor(0, 0, 0, barInfo.swipeAlpha or 0.7)
                -- Per-spell Reverse Swipe: flips this icon's swipe direction away from the bar default
                -- (buffs fill up, cooldowns deplete). Entire block is gated by the session flag, so it
                -- is ZERO cost/ZERO behavior change unless at least one spell has the toggle on -- the
                -- cooldown then keeps DecorateFrame's default. Resolves the frame's CURRENT spell each
                -- pass (so pool reuse + talent overrides stay correct) and re-asserts on every refresh, so toggling off restores the default. Not a per-tick path.
                if ns._cdmAnyReverseSwipe then
                    -- A hosted buff (buff frame on a CD/util bar) uses the BUFF baseline (fill-up), not the cd baseline, so "Reverse" flips the same way it would on a real buffs bar.
                    local rfFc = _ecmeFC[glyph]
                    -- "Fills like a buff" must agree with the claim loops in
                    -- CludesUICdmHooks (DecorateFrame's isBuff, the CD claim
                    -- pass's wantRev): a hosted buff and its placeholder fill UP
                    -- even on a CD/util bar. This pass writes the widget directly,
                    -- so it must also stamp fd._revKind below -- the claim-pass
                    -- repairs are gated on that memo.
                    local rfBuff = (
                        barInfo.barType == "buffs"
                        or barId == "buffs"
                        or barInfo.barType == "custom_buff"
                        or (rfFc and rfFc.isHostedBuff)
                        or (fd and fd._isBuffViewerFrame)
                        or glyph._isPlaceholderFrame
                    )
                            and true
                        or false
                    -- Shared with the decoration + claim re-asserts (ns.EffectiveReverseSwipe),
                    -- so every writer of this widget pushes the same value.
                    local rfReverse = rfBuff
                    if ns.EffectiveReverseSwipe then
                        rfReverse = ns.EffectiveReverseSwipe(glyph, barId, rfBuff)
                    end
                    cd:SetReverse(rfReverse)
                    -- Keep the kind memo equal to what is RENDERED, so the
                    -- kind-gated re-asserts in the claim loops stay sound.
                    if fd then
                        fd._revKind = rfReverse
                    end
                end
                -- Per-spell Hide CD Swipe: removes the cooldown swipe entirely for cd/utility spells
                -- (non-charge -- charge spells use "Hide Swipe (Charges)"). Gated by the session flag,
                -- so zero cost unless someone enables it. Applied here for immediate feedback; the
                -- SetDrawSwipe hook keeps it off against Blizzard's re-pushes. Re-asserts (not hide) each pass so toggling off restores the default swipe -- matching the hook's non-charge force-true.
                if ns._cdmAnyHideCDSwipe and cd.SetDrawSwipe then
                    local isCharge = type(glyph.HasVisualDataSource_Charges) == "function"
                        and glyph:HasVisualDataSource_Charges()
                    if not isCharge then
                        local hsFc = _ecmeFC[glyph]
                        local hsSid = hsFc and hsFc.spellID
                        local hideSw
                        if hsSid then
                            if ns.ResolveSpellSettings then
                                local hsSs = ns.ResolveSpellSettings(glyph, hsSid, ns.GetBarSpellData(barId))
                                hideSw = hsSs and hsSs.hideCDSwipe
                            end
                            if not hideSw and ns.GetEffectiveCustomActiveState then
                                local casH = ns.GetEffectiveCustomActiveState(hsSid)
                                hideSw = casH and casH.hideCDSwipe
                            end
                        end
                        local fd = ns._hookFrameData and ns._hookFrameData[glyph]
                        if fd then
                            fd._isProcessingOverride = true
                        end
                        cd:SetDrawSwipe(not hideSw)
                        if fd then
                            fd._isProcessingOverride = false
                        end
                    end
                end
                -- Per-spell Threshold Text: attach the engine countdown formatter that renders
                -- decimals/a color change below the spell's Threshold Seconds. Gated by the session
                -- flag, so zero cost/zero behavior change unless at least one spell arms it. Resolution
                -- order matches Reverse Swipe above: family store (variant-aware via the frame) first, then the preset/custom customActiveStates entry.
                -- sid resolves canon-first like sidb above -- fc.spellID alone is the cooldownInfo
                -- BASE, which for a hosted buff/debuff can be a generic id shared across icons (or
                -- simply not the id the options menu wrote the entry under), so it misses the armed
                -- per-spell entry entirely. Reuse sidb when the buff block above already computed it.
                if ns._cdmAnyThresholdText and ns.ApplyThresholdFormatter then
                    local ttFc = _ecmeFC[glyph]
                    local ttSid = sidb
                        or (ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(glyph))
                        or (ttFc and ttFc.spellID)
                    local tt
                    if ttSid and ns.ResolveThresholdTextSettings then
                        tt = ns.ResolveThresholdTextSettings(glyph, ttSid, ns.GetBarSpellData(barId), barId)
                    end
                    ns.ApplyThresholdFormatter(cd, tt)
                end
                -- Per-spell "Hide CD Text (Charges)" can additionally hide the recharge numbers while
                -- a charge is in hand; the font block below still styles the text (using the bar's showCD) so it is ready when numbers return.
                local hideCD = not showCD
                if ns.CdmShouldHideCountdown then
                    hideCD = ns.CdmShouldHideCountdown(glyph, hideCD)
                end
                cd:SetHideCountdownNumbers(hideCD)
                -- Apply cooldown text font directly.
                if showCD then
                    local cdFont = GetCDMFont()
                    local cdSize = ((ssb and ssb.cooldownFontSize) or barInfo.cooldownFontSize or 12)
                        * fontScale
                    local cdR = (ssb and ssb.cooldownTextR) or barInfo.cooldownTextR or 1
                    local cdG = (ssb and ssb.cooldownTextG) or barInfo.cooldownTextG or 1
                    local cdB = (ssb and ssb.cooldownTextB) or barInfo.cooldownTextB or 1
                    local cdPosition = (ssb and ssb.cooldownTextPosition)
                        or barInfo.cooldownTextPosition
                        or "center"
                    local cdX = (ssb and ssb.cooldownTextX) or barInfo.cooldownTextX or 0
                    local cdY = (ssb and ssb.cooldownTextY) or barInfo.cooldownTextY or 0
                    -- Find Blizzard's countdown FontString on the Cooldown widget. Keep it ON the
                    -- widget (anchored to cd) so the user's position and X/Y offset work -- REPARENTING
                    -- it makes Blizzard's engine re-center and ignore both. Setting our own anchor also
                    -- overrides the engine's stale baseline (raw SetFont vs SetCountdownFont); off-center anchors are where a missed or stomped anchor first becomes visible.
                    for _, region in pairs({ cd:GetRegions() }) do
                        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                            CludesUI.ApplyIconTextFont(region, cdFont, cdSize, "cdm")
                            region:SetTextColor(cdR, cdG, cdB)
                            ns.AnchorCooldownText(region, cd, cdPosition, cdX, cdY)
                        end
                    end
                end
            end
            -- Update border (PP or textured via ApplyBorderStyle)
            local bdrTgt = (fd and fd.borderFrame) or glyph
            if blizzArt then
            -- Blizzard Style: no CUI border or background (ring + mask instead).
            elseif fd and fd.borderFrame or CludesUI.PP.GetBorders(glyph) then
                local textureKey = barInfo.borderTexture or "solid"
                CludesUI.ApplyBorderStyle(
                    bdrTgt,
                    borderSize,
                    barInfo.borderR or 0,
                    barInfo.borderG or 0,
                    barInfo.borderB or 0,
                    barInfo.borderA or 1,
                    textureKey,
                    barInfo.borderTextureOffset,
                    barInfo.borderTextureOffsetY,
                    barInfo.borderTextureShiftX,
                    barInfo.borderTextureShiftY,
                    "cdm",
                    barInfo.borderThickness or "thin",
                    true,
                    CludesUI.BorderPx(barInfo.borderSizePx, borderSize, textureKey)
                )
            end
            -- Update background
            if backdrop and not blizzArt then
                backdrop:SetColorTexture(
                    barInfo.bgR or 0.08,
                    barInfo.bgG or 0.08,
                    barInfo.bgB or 0.08,
                    barInfo.bgA or 0.6
                )
            end
            -- Style Blizzard's native stack/charge text elements: raise their sub-frames above our
            -- border frame by bumping frame level (safe -- they are Blizzard's own children of the icon and follow frame reuse). Per-icon Charge/Stack override (ssb) falls back to the bar's values.
            local scFont = GetCDMFont()
            local scSize = ((ssb and ssb.stackCountSize) or barInfo.stackCountSize or 11) * fontScale
            local scR = (ssb and ssb.stackCountR) or barInfo.stackCountR or 1
            local scG = (ssb and ssb.stackCountG) or barInfo.stackCountG or 1
            local scB = (ssb and ssb.stackCountB) or barInfo.stackCountB or 1
            local scX = ((ssb and ssb.stackCountX) or barInfo.stackCountX or 0) * fontScale
            local scY = ((ssb and ssb.stackCountY) or barInfo.stackCountY or 0) * fontScale
            -- Stack/charge/item-count text anchor. Default bottom-right keeps the historical +2 vertical nudge so existing bars stay pixel-identical; top and center positions sit flush with no baseline nudge.
            local scPoint
            scPoint, scY = ns.CdmStackAnchorPoint(
                (ssb and ssb.stackCountPosition) or barInfo.stackCountPosition or "bottomright",
                scY
            )
            local showItemCount = barInfo.showItemCount ~= false
            if ssb and ssb.showItemCount ~= nil then
                showItemCount = ssb.showItemCount
            end
            -- Show Item Count "Out of Combat" mode: bar-level combat gate applied on top of the
            -- resolved per-spell value. Combat edges re-run this restyle for OOC bars (ns.RefreshItemCountOOCBars), so the gate only ever reads the event-tracked combat flag.
            if showItemCount and barInfo.itemCountOOC and _inCombat then
                showItemCount = false
            end
            -- Show Charge/Stack Text (buff-family bars; per-spell override wins):
            -- hides both counter lanes via ALPHA -- Blizzard re-shows these
            -- fontstrings on state pushes, so Hide() cannot stick. Alpha is safe
            -- to own HERE only because buff frames never enroll in the cd/utility
            -- zero-charge / Hide Charge Text alpha channel (CdmHooks); non-buff
            -- bars never write (csAlpha nil), so that channel keeps single
            -- ownership of its counters.
            local csAlpha, appsAlpha
            if barInfo.barType == "buffs" or barInfo.barType == "custom_buff" then
                local showCS = barInfo.showChargeStackText ~= false
                if ssb and ssb.showChargeStackText ~= nil then
                    showCS = ssb.showChargeStackText
                end
                csAlpha = showCS and 1 or 0
                appsAlpha = csAlpha
            else
                -- A buff hosted on a cd/utility bar: only its stack counter, which that
                -- bar's charge-text channel never writes, follows the per-spell toggle.
                if fd and fd._isBuffViewerFrame then
                    appsAlpha = (ssb and ssb.showChargeStackText == false) and 0 or 1
                end
            end
            -- Text must render above borders. Levels are relative to the icon's own frame level (CdmHooks: border +13, text +23).
            local textLvl = glyph:GetFrameLevel() + 23
            -- Applications (buff stacks/aura applications) -- not an item count. Blizzard manages show/hide based on whether stacks exist; we only restyle position/font and never gate visibility on showItemCount.
            if glyph.Applications then
                pcall(glyph.Applications.SetFrameLevel, glyph.Applications, textLvl)
                if glyph.Applications.Applications then
                    local appsFS = glyph.Applications.Applications
                    SetBlizzCDMFont(appsFS, scFont, scSize, scR, scG, scB)
                    appsFS:ClearAllPoints()
                    appsFS:SetPoint(scPoint, glyph, scPoint, scX, scY)
                    if appsAlpha then
                        appsFS:SetAlpha(appsAlpha)
                    end
                end
            end
            -- ChargeCount (spell charges like Sigil/Roll) -- not an item count. Blizzard manages show/hide based on charge state.
            if glyph.ChargeCount then
                pcall(glyph.ChargeCount.SetFrameLevel, glyph.ChargeCount, textLvl)
                if glyph.ChargeCount.Current then
                    local chargeFS = glyph.ChargeCount.Current
                    SetBlizzCDMFont(chargeFS, scFont, scSize, scR, scG, scB)
                    chargeFS:ClearAllPoints()
                    chargeFS:SetPoint(scPoint, glyph, scPoint, scX, scY)
                    if csAlpha then
                        chargeFS:SetAlpha(csAlpha)
                    end
                end
            end
            -- Item count text (potions/healthstones) -- our own frame, safe to reparent
            if glyph._itemCountText then
                if txOverlay then
                    glyph._itemCountText:SetParent(txOverlay)
                end
                SetBlizzCDMFont(glyph._itemCountText, scFont, scSize, scR, scG, scB)
                glyph._itemCountText:ClearAllPoints()
                glyph._itemCountText:SetPoint(scPoint, txOverlay or glyph, scPoint, scX, scY)
                if showItemCount then
                    glyph._itemCountText:Show()
                else
                    glyph._itemCountText:Hide()
                end
            end
            -- Custom-spell "Show Charges" count text (our own lazy fontstring from the CdmHooks ticker) follows the same stack/charge text settings.
            if glyph._castCountText then
                ns.StyleCustomChargeText(glyph, barId)
            end

            -- Update keybind text style
            if kbText then
                ns.StyleCDMKeybind(kbText, barInfo, txOverlay, fontScale, GetCDMFont())
            end

            -- Apply custom shape (overrides border/zoom set above). Pass the resolved per-icon
            -- settings so the buff-family Border override (size + color) applies on the authoritative border render, square or shaped.
            local shape = barInfo.iconShape or "none"
            ApplyShapeToCDMIcon(glyph, shape, barInfo, ssb)
            if blizzArt then
                ns.CdmApplyBlizzIconArt(glyph)
            end
            -- A restyle just reset this icon's mask + border level out from under any live fake-active
            -- overlay (border size/shape change while the active window is open). Re-sync the overlay so it re-shapes and re-lifts the border above itself instead of waiting for the next trigger.
            if ns.FakeActive_OnIconRestyled then
                ns.FakeActive_OnIconRestyled(glyph)
            end

            -- Reset glow so glow type change takes effect on next tick. Do NOT reset isActive -- that
            -- causes a 1-frame flash where the ticker sees the transition as "inactive" and un-desaturates
            -- the icon before re-detecting active on the next frame. Preserve proc glow and active state glow across rebuilds.
            local ifd = _getFD(glyph)
            local hadProcGlow = ifd and ifd.procGlowActive
            local hadActiveGlow = ifd and ifd._activeGlowOn
            if hadProcGlow and glowOv then
                -- Stop then restart with per-spell settings
                StopNativeGlow(glowOv)
                if ifd then
                    ifd.procGlowActive = false
                end
                ShowProcGlow(glyph)
                -- A Blackout CD-state glow stays lit beside the proc on its own
                -- overlay: take it down so the pass below restarts it with the
                -- updated settings (or leaves it off when the effect is gone).
                local bo = ifd.blackoutOverlay
                if ifd._cdStateGlowOn and bo and bo._glowActive then
                    StopNativeGlow(bo)
                    ifd._cdStateGlowOn = false
                end
            elseif hadActiveGlow then
                -- Don't touch: active glow is managed by the SetSwipeColor hook. Stopping it here causes a visible blink.
                -- A Blackout CD-state glow has its own overlay: take only that one down,
                -- so the pass below restarts it with the updated settings (or leaves it
                -- off when the effect is gone).
                local bo = ifd.blackoutOverlay
                if ifd._cdStateGlowOn and bo and bo._glowActive then
                    StopNativeGlow(bo)
                    ifd._cdStateGlowOn = false
                end
            elseif ifd and ifd._cdStateGlowOn then
                -- cdState glow active: stop it so the desat hook restarts with the updated style. Also re-evaluate immediately for off-CD spells (desat hook won't fire for those).
                ns.StopCdGlow(ifd)
                ifd._cdStateGlowOn = false
                local fc = _ecmeFC[glyph]
                local spellRef = fc and fc.spellID
                local bk = fc and fc.barKey
                if spellRef and bk then
                    local sd = ns.GetBarSpellData(bk)
                    -- Shared resolver: direct hit + full identity/override matching against the family store, with bar-tier fallback.
                    local ss = ns.ResolveSpellSettings and ns.ResolveSpellSettings(glyph, spellRef, sd, bk)
                    -- The glow half of the effect (any hide beside it runs below).
                    local glow = ns.CdStateGlowOf(ss, glyph)
                    local isReadyGlow = (
                        glow == "pixelGlowReady"
                        or glow == "buttonGlowReady"
                        or glow == "pixelGlowReadyUsable"
                        or glow == "buttonGlowReadyUsable"
                    )
                    local isOnCdGlow = glow == "glowOnCD"
                    if (isReadyGlow or isOnCdGlow) and glowOv then
                        local glowUsable = (glow == "pixelGlowReadyUsable" or glow == "buttonGlowReadyUsable")
                        local glowLive = spellRef
                        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                            glowLive = C_SpellBook.FindSpellOverrideByID(spellRef) or spellRef
                        end
                        local cseInfo = C_Spell.GetSpellCooldown(glowLive)
                        -- Glow (On CD) wants the opposite cooldown state of the ready variants.
                        local wantsGlow
                        if cseInfo then
                            local realCD = ns.CdmOnRealCD(glyph, cseInfo)
                            if isOnCdGlow then
                                wantsGlow = realCD
                            else
                                wantsGlow = not realCD
                            end
                        end
                        if wantsGlow then
                            -- Plain variants glow purely from cooldown state (legacy behavior, zero
                            -- extra reads). Resource Aware variants also require usability, except during the loading-screen settle window (API untrustworthy; the watched-set pass after the window corrects it).
                            local isUsable = true
                            if glowUsable then
                                if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then
                                    isUsable = true
                                else
                                    isUsable = C_Spell.IsSpellUsable and C_Spell.IsSpellUsable(glowLive)
                                end
                            end
                            if isUsable == true then
                                local look = ns.CdReadyGlowStyle(glow, ss)
                                local cr, cg, cb = ns.CdReadyGlowColor(look, ss)
                                ifd._cdStateGlowOn = ns.StartCdGlow(
                                    ifd,
                                    look,
                                    cr,
                                    cg,
                                    cb,
                                    ns.CdReadyGlowAlpha(ss)
                                ) ~= nil
                            end
                        end
                        -- Event-driven re-evaluation: Resource Aware glows always, plus plain/on-CD
                        -- glows on CUI custom frames (their SetDesaturation never fires the
                        -- SetDesaturated hook that would re-evaluate them). Fake-Active-owned
                        -- frames (PresetHasCdState) excluded.
                        local watchGlow = glowUsable
                        if
                            not watchGlow
                            and (glyph._isRacialFrame or glyph._isTrinketFrame or glyph._isPresetFrame or glyph._isItemPresetFrame or glyph._isCustomSpellFrame)
                            and not (ns.PresetHasCdState and ns.PresetHasCdState(glyph))
                        then
                            watchGlow = true
                        end
                        if watchGlow and ns.CDGlowWatch then
                            ns.CDGlowWatch(glyph)
                        end
                    end
                end
            elseif glowOv then
                ns.StopCdGlow(ifd)
                if ifd then
                    ifd.procGlowActive = false
                end
            end

            -- Apply initial cdState effect (hidden/glow) so the state is correct before the first desat tick and before the visibility system runs. Idempotent: re-evaluates current CD state.
            local fc = _ecmeFC[glyph]
            local csSid = fc and fc.spellID
            local csBk = fc and fc.barKey
            if csSid and csBk and csBk:sub(1, 7) ~= "__ghost" then
                local csSd = ns.GetBarSpellData(csBk)
                -- Shared resolver: direct hit + full identity/override matching
                -- against the family store, with bar-tier fallback.
                local csSs = ns.ResolveSpellSettings and ns.ResolveSpellSettings(glyph, csSid, csSd, csBk)
                -- The effect is a hide and a glow, each run on its own below.
                local cse, csGlow = ns.CdStateOf(csSs, glyph)
                -- The hide effects run as their base mode plus flags (ns.CD_STATE_HIDE: Shift Icons, Hidden Until Usable, Hidden Outside Form/Stance), so the branches below stay as-is.
                local m = cse and ns.CD_STATE_HIDE[cse]
                local cseShift, cseUsable, cseForm
                if m then
                    cse, cseShift, cseUsable, cseForm = m.base, m.shift, m.usable, m.form
                end
                -- Stance Bar (CludesUICdmStanceBar.lua): one more hide reason. Alone,
                -- it runs as Hidden (On CD) with the cooldown never read.
                local stance = ns.CdmStanceBarOf(csSs, glyph)
                local stanceOnly = false
                if stance and cse ~= "hiddenOnCD" and cse ~= "hiddenReady" and cse ~= "lowerAlphaOnCD" then
                    cse, stanceOnly = "hiddenOnCD", true
                end
                if cse or csGlow then
                    local csLive = csSid
                    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                        csLive = C_SpellBook.FindSpellOverrideByID(csSid) or csSid
                    end
                    -- realCD is the plain cooldown read the glow runs on; onCD is
                    -- what the hide runs on (the form alone, or unusable counting too).
                    local realCD, onCD
                    if stanceOnly then
                        onCD = false
                    elseif cseForm then
                        -- Only the form decides; form changes re-arm through the form watch.
                        onCD = ns.CdmSpellOutsideForm(csLive)
                        ns.WatchCdUsable(glyph, true)
                    else
                        realCD = ns.CdmOnRealCD(glyph, C_Spell.GetSpellCooldown(csLive))
                        onCD = realCD
                    end
                    if cseUsable then
                        if not onCD then
                            onCD = ns.CdmSpellNotUsable(csLive)
                        end
                        -- Proc edges change only usability: SPELL_UPDATE_USABLE watch.
                        ns.WatchCdUsable(glyph)
                    end
                    local sHide, sShift = false, false
                    if stance then
                        sHide, sShift = ns.CdmStanceBarHidden(stance)
                        -- Page changes re-arm through the stance bar watch.
                        ns.WatchCdUsable(glyph, cseForm, true, cseUsable)
                    end
                    if sHide then
                        glyph:SetAlpha(0)
                        if fc then
                            fc._cdStateHidden = true
                            if ns.SetCdStateShiftHidden then
                                ns.SetCdStateShiftHidden(fc, sShift)
                            end
                        end
                    elseif cse == "hiddenOnCD" or cse == "hiddenReady" then
                        local hide
                        if cse == "hiddenOnCD" then
                            hide = onCD and true or false
                        else
                            -- Hidden (CD Ready): on a charge spell "ready" means AT MAX charges, so the icon keeps tracking the recharge instead of vanishing with a charge still down (ns.CdmCdStateReady).
                            hide = ns.CdmCdStateReady(csLive, onCD, csSs.chargeHideUntilSpent)
                            -- The refill-to-max edge fires no visual hook, so register the SPELL_UPDATE_CHARGES watch that re-hides the icon when it tops off. Self-skips non-charge spells.
                            ns.WatchCdStateChargeIfEnabled(glyph)
                        end
                        glyph:SetAlpha(hide and 0 or IconShownAlpha(fc, barInfo))
                        if fc then
                            fc._cdStateHidden = hide or false
                            if ns.SetCdStateShiftHidden then
                                ns.SetCdStateShiftHidden(fc, cseShift and hide or false)
                            end
                        end
                    elseif cse == "lowerAlphaOnCD" then
                        -- Identical to hiddenOnCD but with a customizable opacity instead of 0. Reuse
                        -- the _cdStateHidden flag as "cd-state owns this alpha" so the opacity appliers leave the lowered value alone. A visibility-hidden bar stays at 0 in both states.
                        local csBase = IconShownAlpha(fc, barInfo)
                        glyph:SetAlpha(
                            csBase == 0 and 0 or (onCD and (csSs.cdStateLowerAlpha or 0.5) or csBase)
                        )
                        if fc then
                            fc._cdStateHidden = onCD or false
                            if ns.SetCdStateShiftHidden then
                                ns.SetCdStateShiftHidden(fc, false)
                            end
                        end
                    else
                        -- No hide effect: clear stale hidden state
                        if fc and fc._cdStateHidden then
                            fc._cdStateHidden = false
                            glyph:SetAlpha(IconShownAlpha(fc, barInfo))
                        end
                        if fc and ns.SetCdStateShiftHidden then
                            ns.SetCdStateShiftHidden(fc, false)
                        end
                    end
                    if csGlow then
                        if realCD == nil then
                            realCD = ns.CdmOnRealCD(glyph, C_Spell.GetSpellCooldown(csLive))
                        end
                        -- A live proc or active-state glow keeps the shared overlay:
                        -- ns.StartCdGlow lights only a Blackout beside it.
                        if not ifd or not ifd._cdStateGlowOn then
                            local isReadyGlow = (
                                csGlow == "pixelGlowReady"
                                or csGlow == "buttonGlowReady"
                                or csGlow == "pixelGlowReadyUsable"
                                or csGlow == "buttonGlowReadyUsable"
                            )
                            local isOnCdGlow = csGlow == "glowOnCD"
                            local wantsGlow = (isOnCdGlow and realCD) or (isReadyGlow and not realCD)
                            if wantsGlow and glowOv then
                                -- Plain variants glow purely from cooldown state (legacy). Resource Aware variants also require usability outside the loading-screen settle window.
                                local isUsable = true
                                if csGlow == "pixelGlowReadyUsable" or csGlow == "buttonGlowReadyUsable" then
                                    if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then
                                        isUsable = true
                                    else
                                        isUsable = C_Spell.IsSpellUsable and C_Spell.IsSpellUsable(csLive)
                                    end
                                end
                                if isUsable == true and ifd then
                                    local look = ns.CdReadyGlowStyle(csGlow, csSs)
                                    local cr, cg, cb = ns.CdReadyGlowColor(look, csSs)
                                    ifd._cdStateGlowOn = ns.StartCdGlow(
                                        ifd,
                                        look,
                                        cr,
                                        cg,
                                        cb,
                                        ns.CdReadyGlowAlpha(csSs)
                                    ) ~= nil
                                end
                            end
                        end
                        -- Resource Aware glows always watch cooldown events. Plain/on-CD glows normally
                        -- re-evaluate through the SetDesaturated hook, but CUI's custom frames
                        -- (racial/trinket/potion/custom) drive desaturation via SetDesaturation(float),
                        -- which never fires that hook -- without a watch their glow stays lit for the
                        -- whole cooldown. Frames owned by the Fake-Active preset path (PresetHasCdState) are excluded; that engine glows them.
                        local watchGlow = csGlow == "pixelGlowReadyUsable"
                            or csGlow == "buttonGlowReadyUsable"
                        if
                            not watchGlow
                            and (csGlow == "pixelGlowReady" or csGlow == "buttonGlowReady" or csGlow == "glowOnCD")
                            and (glyph._isRacialFrame or glyph._isTrinketFrame or glyph._isPresetFrame or glyph._isItemPresetFrame or glyph._isCustomSpellFrame)
                            and not (ns.PresetHasCdState and ns.PresetHasCdState(glyph))
                        then
                            watchGlow = true
                        end
                        if watchGlow and glowOv and ns.CDGlowWatch then
                            ns.CDGlowWatch(glyph)
                        end
                    end
                elseif fc and (fc._cdStateHidden or fc._cdStateShiftHidden) then
                    -- A preset keeps its hidden state from the Fake-Active engine (its cdState lives in customActiveStates, not per-bar spellSettings), so don't clear it here or the icon flashes visible.
                    if not (ns.PresetHasCdState and ns.PresetHasCdState(glyph)) then
                        fc._cdStateHidden = false
                        glyph:SetAlpha(IconShownAlpha(fc, barInfo))
                        if ns.SetCdStateShiftHidden then
                            ns.SetCdStateShiftHidden(fc, false)
                        end
                    end
                end
            end
            -- Ignore Resource Cost: repaint now, as a settings change brings no
            -- Blizzard tint write for the hook to follow (one flag read when unused).
            if ns._cdmAnyNoResourceTint and ns.CdmApplyResourceTint then
                ns.CdmApplyResourceTint(glyph, fd)
            end
        end -- not icon._isEmptySlotFrame
        -- Only Show Numbers (bar setting): re-hide the icon art AFTER the passes above re-applied
        -- borders/shapes/textures, so the countdown number is all that remains. One field read when the bar is off; also restores one-shot right after the bar toggles off.
        -- Re-fetched (never the wrapped block's `fd`): always nil for an Empty Slot, and cheap
        -- either way, so both kinds share this one line without widening the skip above.
        if ns.ApplyOnlyNumbers then
            ns.ApplyOnlyNumbers(glyph, _getFD(glyph), barInfo)
        end
    end
end
ns.RefreshCDMIconAppearance = RefreshCDMIconAppearance

Inner.RefreshCDMIconAppearance = RefreshCDMIconAppearance
Inner.broken = false
