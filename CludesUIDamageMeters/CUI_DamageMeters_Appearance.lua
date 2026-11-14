if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Optional row decorations use window overlays with their own viewport clips.
local _, mod = ...
local Inner = mod._dmInternals
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local CUI, Pix = CludesUI, CludesUI.PP
local cached, generation = nil, 0

function mod.DMInvalidateAppearance()
    if cached then
        cached, generation = nil, generation + 1
    end
end

function mod.DMUseBarSeparators(c)
    return c.barSeparators
        and not c.borderFollowFill
        and not mod.DMBlizz()
        and (c.borderSize or 0) > 0
        and CUI.GetBorderCompanion(c.borderTexture, "sepH") ~= nil
end

function mod.DMUsesRowSeparators(c)
    return mod.DMUseBarSeparators(c)
        or (
            c.iconSeparator
            and (c.iconStyle or "spec") ~= "none"
            and not mod.DMBlizz()
            and (c.borderSize or 0) > 0
            and CUI.GetBorderCompanion(c.borderTexture, "sepV") ~= nil
        )
end

-- Returns true when the window border moved to another level (the row
-- decorations take their level from it).
function mod.DMSetWindowBorderLayer(wid, c)
    local level = wid.header:GetFrameLevel() + 4
    if c.windowBorderBehind then
        level = math.max(0, wid.frame:GetFrameLevel() - 1)
    elseif mod.DMUsesRowSeparators(c) then
        level = wid.header:GetFrameLevel() + 10
    end
    if wid.windowBorderTarget:GetFrameLevel() ~= level then
        wid.windowBorderTarget:SetFrameLevel(level)
        if wid._headerSeparator then
            wid._headerSeparator:SetFrameLevel(level + 2)
            wid._headerSeparator.art:SetFrameLevel(level + 3)
        end
        return true
    end
    return false
end

function mod.DMRefreshRowDecor(window)
    local c = mod.EDM.DB()
    if c.barSeparators or c.iconSeparator or c.showPlayerMarker or window._decorSync then
        mod.DMSetWindowBorderLayer(window, c)
        window.Refresh()
    end
end

function mod.DMPrepareValueGradient(window, sources, total)
    local range = window._valueGradientRange
    if not range then
        range = {}
        window._valueGradientRange = range
    end
    range.count, range.low, range.high, range.key = total, nil, nil, nil
    local kindOf = window.curDMType
    if kindOf == "threat" or kindOf == Enum.DamageMeterType.Deaths then
        return
    end
    local perSecond = mod.EDM.DB().numberFormat == 0
        and kindOf ~= Enum.DamageMeterType.Interrupts
        and kindOf ~= Enum.DamageMeterType.Dispels
    range.key = perSecond and "amountPerSecond" or "totalAmount"
    for idx = 1, total do
        local value = sources[idx][range.key]
        -- Secret sessions use the API's existing rank order instead of reading amounts.
        if (issecretvalue and issecretvalue(value)) or type(value) ~= "number" then
            range.low, range.high = nil, nil
            return
        end
        range.low = range.low and math.min(range.low, value) or value
        range.high = range.high and math.max(range.high, value) or value
    end
end

function mod.DMPaintValueGradient(barFrame, window, source, slotPos)
    local t
    if window.curDMType == "threat" then
        local value = source.threatScaled
        t = not (issecretvalue and issecretvalue(value)) and type(value) == "number" and value / 100 or 0
    else
        local range = window._valueGradientRange
        t = range.count > 1 and (slotPos - 1) / (range.count - 1) or 0
        local value = range.key and source[range.key]
        if range.low and not (issecretvalue and issecretvalue(value)) and type(value) == "number" then
            t = range.high > range.low and (range.high - value) / (range.high - range.low) or 0
        end
    end
    t = math.max(0, math.min(1, t)) * 2
    -- Painted only when the colour moves; the row's other colour passes clear
    -- the memo (a full rebuild, the pinned row's hand-back).
    if barFrame._gradT == t then
        return
    end
    barFrame._gradT = t
    barFrame.amount:SetTextColor(math.min(1, t), math.min(1, 2 - t), 0)
end

local function Style(c)
    if cached and cached.cfg == c then
        return cached
    end
    local pixels = not mod.DMBlizz()
        and (c.borderSize or 0) > 0
        and CUI.GetBorderCompanion(c.borderTexture, "sepH") ~= nil
    cached = {
        cfg = c,
        bars = mod.DMUseBarSeparators(c),
        icons = c.iconSeparator and pixels and (c.iconStyle or "spec") ~= "none",
        marker = c.showPlayerMarker,
    }
    return cached
end

local function NewTexture(hostRegion, subFrame, art)
    local texture = (art or hostRegion.art):CreateTexture(nil, "OVERLAY", nil, subFrame or 0)
    Pix.DisablePixelSnap(texture)
    return texture
end

-- Parks a host (hidden, out of the UI-scale pass). Returns at once when it is
-- parked already: the marker-only mode parks every other row's host each refresh.
local function HideRowDecor(hostRegion)
    if hostRegion.active == false and hostRegion.shownAs == false then
        return
    end
    hostRegion.active, hostRegion.shownAs, hostRegion.placed = false, false, nil
    hostRegion:Hide()
    if hostRegion.iconHost then
        hostRegion.iconHost:Hide()
    end
    CUI.RegisterPxReapply(hostRegion, nil)
end

-- Follows the row. Re-anchors only when the scroll, the row metrics, the row
-- count, the viewport height or the pin state moved since the last placement
-- (host.placed); slot, icon and style changes clear it (ReapplyRowDecor).
local function PositionRowDecor(hostRegion)
    local wid, barFrame = hostRegion.window, hostRegion.bar
    local visible = (hostRegion.active and barFrame.row:IsShown() and wid.viewport:IsShown()) and true
        or false
    if hostRegion.shownAs ~= visible then
        hostRegion.shownAs = visible
        hostRegion:SetShown(visible)
        if hostRegion.iconHost then
            hostRegion.iconHost:SetShown(visible)
        end
    end
    if not visible then
        return
    end
    local es = hostRegion:GetEffectiveScale()
    local hgt, _, stride =
        mod._RowMetrics(hostRegion.style.cfg.barHeight or 18, hostRegion.style.cfg.barSpacing or 2, es)
    local scroll = hostRegion.slot > 0 and wid.viewport:GetVerticalScroll() or 0
    local total, viewH = wid.visibleCount or 0, wid.viewport:GetHeight()
    local atTop = wid.stickyAtTop == true
    local pinBottom = hostRegion.slot > 0 and not atTop and wid.stickyPlayer.row:IsShown()
    if
        hostRegion.placed
        and hostRegion.pEs == es
        and hostRegion.pH == hgt
        and hostRegion.pStride == stride
        and hostRegion.pScroll == scroll
        and hostRegion.pCount == total
        and hostRegion.pViewH == viewH
        and hostRegion.pAtTop == atTop
        and hostRegion.pPinBottom == pinBottom
    then
        return false
    end
    hostRegion.placed, hostRegion.pEs, hostRegion.pH, hostRegion.pStride, hostRegion.pScroll =
        true, es, hgt, stride, scroll
    hostRegion.pCount, hostRegion.pViewH, hostRegion.pAtTop, hostRegion.pPinBottom =
        total, viewH, atTop, pinBottom
    local joinBottom = hostRegion.style.icons
            and pinBottom
            and hostRegion.slot == math.ceil((scroll + viewH) / stride)
        or false
    local joinChanged = hostRegion.joinBottom ~= joinBottom
    hostRegion.joinBottom = joinBottom
    -- Keep the end separator when the whole list fits without scrolling.
    hostRegion.lineVisible = hostRegion.style.bars
        and (
            hostRegion.slot <= 0
            or (hostRegion.slot < total and hostRegion.slot * stride < scroll + viewH)
            or (hostRegion.slot == total and total * stride <= viewH)
        )
    if hostRegion.line then
        hostRegion.line:SetShown(hostRegion.lineVisible)
    end
    local clip = hostRegion.slot <= 0 and wid.frame or wid.viewport
    hostRegion:ClearAllPoints()
    hostRegion:SetAllPoints(clip)
    hostRegion.art:ClearAllPoints()
    if hostRegion.slot <= 0 then
        hostRegion.art:SetAllPoints(barFrame.row)
    else
        local posY = scroll - (hostRegion.slot - 1) * stride
        hostRegion.art:SetPoint("TOPLEFT", wid.viewport, "TOPLEFT", 0, posY)
        hostRegion.art:SetPoint("TOPRIGHT", wid.viewport, "TOPRIGHT", 0, posY)
        hostRegion.art:SetHeight(hgt)
    end
    hostRegion.fill:ClearAllPoints()
    hostRegion.fill:SetPoint("TOPLEFT", hostRegion.art, "TOPLEFT", hostRegion.iconShown and hgt or 0, 0)
    hostRegion.fill:SetPoint("BOTTOMRIGHT", hostRegion.art, "BOTTOMRIGHT", 0, 0)
    if hostRegion.iconHost then
        hostRegion.iconHost:ClearAllPoints()
        hostRegion.iconHost:SetPoint(
            "TOPLEFT",
            clip,
            "TOPLEFT",
            0,
            hostRegion.slot > 0 and wid.stickyAtTop and Pix.perfect / es or 0
        )
        -- Let the scrolling dividers reach the one-pixel rail above a bottom-pinned row.
        local bottom = pinBottom and -Pix.perfect / es or 0
        hostRegion.iconHost:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, bottom)
    end
    return joinChanged
end

local function PlaceRow(hostRegion)
    local c = hostRegion.style.cfg
    local rowFrame, fillTex = hostRegion.art, hostRegion.fill
    local es = hostRegion:GetEffectiveScale()
    local hgt, gap = mod._RowMetrics(c.barHeight or 18, c.barSpacing or 2, es)
    local key, step = c.borderTexture, c.borderSize or 0
    local px = CUI.BorderPx(c.borderSizePx, step, key)
    local thick = CUI.BorderCompanionThickness(key, step, px, es)
    local r, g, b, a = c.borderR or 0, c.borderG or 0, c.borderB or 0, c.borderA or 1
    if hostRegion.style.bars then
        if not hostRegion.line then
            hostRegion.line = NewTexture(hostRegion)
        end
        local texture = hostRegion.line
        local lead = Pix.SnapForES(thick * 2 / CUI.GetBorderCompanion(key, "sepSize"), es)
        texture:SetTexture(CUI.GetBorderCompanion(key, "sepH"))
        texture:SetVertexColor(r, g, b, a)
        texture:ClearAllPoints()
        if hostRegion.slot == -1 then
            texture:SetTexCoord(0, 1, 0, 1)
            texture:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 0, lead)
            texture:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", 0, lead)
        else
            local posY = Pix.SnapForES(-(hostRegion.slot == 0 and 0 or gap / 2) - lead, es)
            texture:SetTexCoord(0, 1, 1, 0)
            texture:SetPoint("BOTTOMLEFT", rowFrame, "BOTTOMLEFT", 0, posY)
            texture:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", 0, posY)
        end
        texture:SetHeight(thick)
        texture:SetShown(hostRegion.lineVisible)
    elseif hostRegion.line then
        hostRegion.line:Hide()
    end
    if hostRegion.style.icons and hostRegion.iconShown then
        if not hostRegion.iconLine then
            -- A sibling clip escapes the scroll frame's flattened render order.
            hostRegion.iconHost = CreateFrame("Frame", nil, hostRegion.window.frame)
            hostRegion.iconHost:SetClipsChildren(true)
            hostRegion.iconHost:EnableMouse(false)
            hostRegion.iconHost:SetFrameStrata(hostRegion.strata)
            hostRegion.iconHost:SetFrameLevel(hostRegion.level + 1)
            hostRegion.iconArt = CreateFrame("Frame", nil, hostRegion.iconHost)
            hostRegion.iconArt:SetAllPoints(rowFrame)
            hostRegion.iconArt:EnableMouse(false)
            hostRegion.iconArt:SetFrameStrata(hostRegion.strata)
            hostRegion.iconArt:SetFrameLevel(hostRegion.level + 2)
            hostRegion.iconLine = NewTexture(hostRegion, 1, hostRegion.iconArt)
            -- The new clip takes the host's shown state and anchors.
            hostRegion.shownAs, hostRegion.placed = nil, nil
            PositionRowDecor(hostRegion)
        end
        local texture = hostRegion.iconLine
        CUI.PlaceBorderDividerV(texture, fillTex, false, false, key, step, px, es)
        local topY, bottom = 0, 0
        -- Pinned rows have a separate rail; the scrolling row trims shorten their divider.
        if hostRegion.style.bars and hostRegion.slot > 0 then
            if hostRegion.slot > 1 then
                topY = math.max(0, thick / 32 - gap / 2)
            end
            bottom = math.max(0, thick * 3 / 32 - gap / 2)
        end
        topY = Pix.SnapForES(topY, es)
        if hostRegion.slot > 0 and (hostRegion.slot ~= 1 or hostRegion.pinTop) then
            topY = topY - Pix.perfect / es
        elseif hostRegion.slot == -1 then
            topY = topY + Pix.perfect / es
        end
        bottom = Pix.SnapForES(bottom, es)
        if hostRegion.joinBottom then
            bottom = bottom - Pix.perfect / es
        end
        if hostRegion.slot == 0 then
            bottom = bottom + Pix.perfect / es
        end
        if topY + bottom >= hgt then
            texture:Hide()
        else
            local lead = Pix.SnapForES(thick * 2 / CUI.GetBorderCompanion(key, "sepSize"), es)
            texture:SetPoint("TOPLEFT", fillTex, "TOPLEFT", -lead, -topY)
            texture:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMLEFT", -lead, bottom)
        end
        texture:SetVertexColor(r, g, b, a)
    elseif hostRegion.iconLine then
        hostRegion.iconLine:Hide()
    end
    if hostRegion.own and hostRegion.style.marker then
        if not hostRegion.marker then
            hostRegion.marker = NewTexture(hostRegion, 2)
            hostRegion.marker:SetPoint("TOPLEFT", fillTex, "TOPLEFT")
            hostRegion.marker:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMLEFT")
            hostRegion.marker:SetWidth(2)
            hostRegion.marker:SetColorTexture(1, 1, 1, 0.95)
        end
        hostRegion.marker:Show()
    elseif hostRegion.marker then
        hostRegion.marker:Hide()
    end
end

-- A full re-placement (a new slot, icon or style, a pin flip, a new pixel grid).
local function ReapplyRowDecor(hostRegion)
    hostRegion.placed = nil
    PositionRowDecor(hostRegion)
    PlaceRow(hostRegion)
end

local function SyncRowDecor(hostRegion, enabled)
    if not enabled then
        HideRowDecor(hostRegion)
        return
    end
    local pinTop = hostRegion.window.stickyAtTop == true
    if hostRegion.active and hostRegion.pinTop ~= pinTop then
        hostRegion.pinTop = pinTop
        ReapplyRowDecor(hostRegion)
    elseif PositionRowDecor(hostRegion) then
        PlaceRow(hostRegion)
    end
end

function mod.DMSyncRowDecor(wid)
    local c = mod.EDM.DB()
    local enabled = c.barSeparators or c.iconSeparator or c.showPlayerMarker
    for _, barFrame in ipairs(wid.rowPool) do
        -- A parked host has nothing to follow.
        local hostRegion = barFrame._decor
        if hostRegion and (hostRegion.active or not enabled) then
            SyncRowDecor(hostRegion, enabled)
        end
    end
    if wid.stickyPlayer._decor then
        SyncRowDecor(wid.stickyPlayer._decor, enabled)
    end
    wid._decorSync = enabled or nil
end

function mod.DMApplyRowDecor(barFrame, window, source, slotIndex)
    local c, hostRegion = mod.EDM.DB(), barFrame._decor
    if not (c.barSeparators or c.iconSeparator or c.showPlayerMarker) then
        if hostRegion then
            HideRowDecor(hostRegion)
        end
        return
    end
    local look = Style(c)
    local own = look.marker and mod._IsOwnRow(source) or false
    if not look.bars and not look.icons and not own then
        if hostRegion then
            HideRowDecor(hostRegion)
        end
        return
    end
    if not hostRegion then
        hostRegion = CreateFrame("Frame", nil, window.frame)
        hostRegion:SetClipsChildren(true)
        hostRegion:EnableMouse(false)
        hostRegion.art = CreateFrame("Frame", nil, hostRegion)
        hostRegion.art:EnableMouse(false)
        hostRegion.fill = CreateFrame("Frame", nil, hostRegion.art)
        hostRegion.fill:EnableMouse(false)
        hostRegion.bar, hostRegion.window, barFrame._decor = barFrame, window, hostRegion
    end
    -- Shared levels keep every icon divider above every bar divider, including pinned rows.
    local rowLevel = window.stickyPlayer and window.stickyPlayer.row:GetFrameLevel()
        or window.frame:GetFrameLevel() + 8
    local level = math.max(window.windowBorderTarget:GetFrameLevel() + 4, rowLevel + 7)
    local scale, iconShown = hostRegion:GetEffectiveScale(), barFrame.classIcon:IsShown()
    local strata = window.frame:GetFrameStrata()
    local pinTop = window.stickyAtTop == true
    if
        hostRegion:IsShown()
        and hostRegion.gen == generation
        and hostRegion.style == look
        and hostRegion.slot == slotIndex
        and hostRegion.own == own
        and hostRegion.iconShown == iconShown
        and hostRegion.level == level
        and hostRegion.scale == scale
        and hostRegion.strata == strata
        and hostRegion.pinTop == pinTop
    then
        if PositionRowDecor(hostRegion) then
            PlaceRow(hostRegion)
        end
        return
    end
    hostRegion.gen, hostRegion.style, hostRegion.slot, hostRegion.own = generation, look, slotIndex, own
    hostRegion.iconShown, hostRegion.level, hostRegion.scale, hostRegion.strata =
        iconShown, level, scale, strata
    hostRegion.pinTop = pinTop
    hostRegion.active, window._decorSync = true, true
    hostRegion:SetFrameStrata(strata)
    hostRegion:SetFrameLevel(level)
    hostRegion.art:SetFrameStrata(strata)
    hostRegion.art:SetFrameLevel(level + 1)
    if hostRegion.iconArt then
        hostRegion.iconHost:SetFrameStrata(strata)
        hostRegion.iconHost:SetFrameLevel(level + 1)
        hostRegion.iconArt:SetFrameStrata(strata)
        hostRegion.iconArt:SetFrameLevel(level + 2)
    end
    ReapplyRowDecor(hostRegion)
    CUI.RegisterPxReapply(
        hostRegion,
        (look.icons or (look.bars and c.borderSizePx)) and ReapplyRowDecor or nil
    )
end

local function PlaceHeader(hostRegion)
    local wid, c = hostRegion.window, mod.EDM.DB()
    local es = hostRegion:GetEffectiveScale()
    local key, step = c.windowBorderTexture, c.windowBorderSize
    local px = CUI.BorderPx(c.windowBorderSizePx, step, key)
    local thick = CUI.BorderCompanionThickness(key, step, px, es)
    local lead = Pix.SnapForES(thick * 2 / CUI.GetBorderCompanion(key, "sepSize"), es)
    local texture, color = hostRegion.line, c.windowBorderColor or {}
    texture:SetTexture(CUI.GetBorderCompanion(key, "sepH"))
    texture:SetTexCoord(0, 1, 1, 0)
    texture:SetVertexColor(color.r or 0, color.g or 0, color.b or 0, color.a or 1)
    texture:ClearAllPoints()
    texture:SetPoint("BOTTOMLEFT", wid.header, "BOTTOMLEFT", 0, -lead)
    texture:SetPoint("BOTTOMRIGHT", wid.header, "BOTTOMRIGHT", 0, -lead)
    texture:SetHeight(thick)
end

function mod.DMApplyHeaderSeparator(wid)
    local c, hostRegion = mod.EDM.DB(), wid._headerSeparator
    local enabled = c.hdrBottomSeparator
        and not mod.DMBlizz()
        and c.windowBorderIncludeHeader ~= false
        and (c.windowBorderSize or 0) > 0
        and CUI.GetBorderCompanion(c.windowBorderTexture, "sepH") ~= nil
    if not enabled then
        if hostRegion then
            hostRegion:Hide()
            CUI.RegisterPxReapply(hostRegion, nil)
            if not mod.DMBlizz() then
                wid.header._bottomBorder:SetShown((c.hdrBottomBorderSize or 0) > 0)
            end
        end
        return
    end
    if not hostRegion then
        hostRegion = CreateFrame("Frame", nil, wid.frame)
        hostRegion:SetAllPoints(wid.frame)
        hostRegion:SetClipsChildren(true)
        hostRegion:EnableMouse(false)
        hostRegion.art = CreateFrame("Frame", nil, hostRegion)
        hostRegion.art:SetAllPoints(wid.header)
        hostRegion.art:EnableMouse(false)
        hostRegion.line = NewTexture(hostRegion)
        hostRegion.window, wid._headerSeparator = wid, hostRegion
    end
    hostRegion:SetFrameStrata(wid.frame:GetFrameStrata())
    hostRegion:SetFrameLevel(wid.windowBorderTarget:GetFrameLevel() + 2)
    hostRegion.art:SetFrameLevel(hostRegion:GetFrameLevel() + 1)
    wid.header._bottomBorder:Hide()
    hostRegion:Show()
    PlaceHeader(hostRegion)
    CUI.RegisterPxReapply(hostRegion, c.windowBorderSizePx and PlaceHeader or nil)
end

Inner.broken = false
