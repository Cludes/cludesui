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
    local kind = window.curDMType
    if kind == "threat" or kind == Enum.DamageMeterType.Deaths then
        return
    end
    local perSecond = mod.EDM.DB().numberFormat == 0
        and kind ~= Enum.DamageMeterType.Interrupts
        and kind ~= Enum.DamageMeterType.Dispels
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

function mod.DMPaintValueGradient(bar, window, source, index)
    local t
    if window.curDMType == "threat" then
        local value = source.threatScaled
        t = not (issecretvalue and issecretvalue(value)) and type(value) == "number" and value / 100 or 0
    else
        local range = window._valueGradientRange
        t = range.count > 1 and (index - 1) / (range.count - 1) or 0
        local value = range.key and source[range.key]
        if range.low and not (issecretvalue and issecretvalue(value)) and type(value) == "number" then
            t = range.high > range.low and (range.high - value) / (range.high - range.low) or 0
        end
    end
    t = math.max(0, math.min(1, t)) * 2
    -- Painted only when the colour moves; the row's other colour passes clear
    -- the memo (a full rebuild, the pinned row's hand-back).
    if bar._gradT == t then
        return
    end
    bar._gradT = t
    bar.amount:SetTextColor(math.min(1, t), math.min(1, 2 - t), 0)
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

local function NewTexture(host, sub, art)
    local texture = (art or host.art):CreateTexture(nil, "OVERLAY", nil, sub or 0)
    Pix.DisablePixelSnap(texture)
    return texture
end

-- Parks a host (hidden, out of the UI-scale pass). Returns at once when it is
-- parked already: the marker-only mode parks every other row's host each refresh.
local function HideRowDecor(host)
    if host.active == false and host.shownAs == false then
        return
    end
    host.active, host.shownAs, host.placed = false, false, nil
    host:Hide()
    if host.iconHost then
        host.iconHost:Hide()
    end
    CUI.RegisterPxReapply(host, nil)
end

-- Follows the row. Re-anchors only when the scroll, the row metrics, the row
-- count, the viewport height or the pin state moved since the last placement
-- (host.placed); slot, icon and style changes clear it (ReapplyRowDecor).
local function PositionRowDecor(host)
    local wid, bar = host.window, host.bar
    local visible = (host.active and bar.row:IsShown() and wid.viewport:IsShown()) and true or false
    if host.shownAs ~= visible then
        host.shownAs = visible
        host:SetShown(visible)
        if host.iconHost then
            host.iconHost:SetShown(visible)
        end
    end
    if not visible then
        return
    end
    local es = host:GetEffectiveScale()
    local hgt, _, stride = mod._RowMetrics(host.style.cfg.barHeight or 18, host.style.cfg.barSpacing or 2, es)
    local scroll = host.slot > 0 and wid.viewport:GetVerticalScroll() or 0
    local total, viewH = wid.visibleCount or 0, wid.viewport:GetHeight()
    local atTop = wid.stickyAtTop == true
    local pinBottom = host.slot > 0 and not atTop and wid.stickyPlayer.row:IsShown()
    if
        host.placed
        and host.pEs == es
        and host.pH == hgt
        and host.pStride == stride
        and host.pScroll == scroll
        and host.pCount == total
        and host.pViewH == viewH
        and host.pAtTop == atTop
        and host.pPinBottom == pinBottom
    then
        return false
    end
    host.placed, host.pEs, host.pH, host.pStride, host.pScroll = true, es, hgt, stride, scroll
    host.pCount, host.pViewH, host.pAtTop, host.pPinBottom = total, viewH, atTop, pinBottom
    local joinBottom = host.style.icons and pinBottom and host.slot == math.ceil((scroll + viewH) / stride)
        or false
    local joinChanged = host.joinBottom ~= joinBottom
    host.joinBottom = joinBottom
    -- Keep the end separator when the whole list fits without scrolling.
    host.lineVisible = host.style.bars
        and (
            host.slot <= 0
            or (host.slot < total and host.slot * stride < scroll + viewH)
            or (host.slot == total and total * stride <= viewH)
        )
    if host.line then
        host.line:SetShown(host.lineVisible)
    end
    local clip = host.slot <= 0 and wid.frame or wid.viewport
    host:ClearAllPoints()
    host:SetAllPoints(clip)
    host.art:ClearAllPoints()
    if host.slot <= 0 then
        host.art:SetAllPoints(bar.row)
    else
        local posY = scroll - (host.slot - 1) * stride
        host.art:SetPoint("TOPLEFT", wid.viewport, "TOPLEFT", 0, posY)
        host.art:SetPoint("TOPRIGHT", wid.viewport, "TOPRIGHT", 0, posY)
        host.art:SetHeight(hgt)
    end
    host.fill:ClearAllPoints()
    host.fill:SetPoint("TOPLEFT", host.art, "TOPLEFT", host.iconShown and hgt or 0, 0)
    host.fill:SetPoint("BOTTOMRIGHT", host.art, "BOTTOMRIGHT", 0, 0)
    if host.iconHost then
        host.iconHost:ClearAllPoints()
        host.iconHost:SetPoint(
            "TOPLEFT",
            clip,
            "TOPLEFT",
            0,
            host.slot > 0 and wid.stickyAtTop and Pix.perfect / es or 0
        )
        -- Let the scrolling dividers reach the one-pixel rail above a bottom-pinned row.
        local bottom = pinBottom and -Pix.perfect / es or 0
        host.iconHost:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, bottom)
    end
    return joinChanged
end

local function PlaceRow(host)
    local c = host.style.cfg
    local row, fill = host.art, host.fill
    local es = host:GetEffectiveScale()
    local hgt, gap = mod._RowMetrics(c.barHeight or 18, c.barSpacing or 2, es)
    local key, step = c.borderTexture, c.borderSize or 0
    local px = CUI.BorderPx(c.borderSizePx, step, key)
    local thick = CUI.BorderCompanionThickness(key, step, px, es)
    local r, g, b, a = c.borderR or 0, c.borderG or 0, c.borderB or 0, c.borderA or 1
    if host.style.bars then
        if not host.line then
            host.line = NewTexture(host)
        end
        local texture = host.line
        local lead = Pix.SnapForES(thick * 2 / CUI.GetBorderCompanion(key, "sepSize"), es)
        texture:SetTexture(CUI.GetBorderCompanion(key, "sepH"))
        texture:SetVertexColor(r, g, b, a)
        texture:ClearAllPoints()
        if host.slot == -1 then
            texture:SetTexCoord(0, 1, 0, 1)
            texture:SetPoint("TOPLEFT", row, "TOPLEFT", 0, lead)
            texture:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, lead)
        else
            local posY = Pix.SnapForES(-(host.slot == 0 and 0 or gap / 2) - lead, es)
            texture:SetTexCoord(0, 1, 1, 0)
            texture:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, posY)
            texture:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, posY)
        end
        texture:SetHeight(thick)
        texture:SetShown(host.lineVisible)
    elseif host.line then
        host.line:Hide()
    end
    if host.style.icons and host.iconShown then
        if not host.iconLine then
            -- A sibling clip escapes the scroll frame's flattened render order.
            host.iconHost = CreateFrame("Frame", nil, host.window.frame)
            host.iconHost:SetClipsChildren(true)
            host.iconHost:EnableMouse(false)
            host.iconHost:SetFrameStrata(host.strata)
            host.iconHost:SetFrameLevel(host.level + 1)
            host.iconArt = CreateFrame("Frame", nil, host.iconHost)
            host.iconArt:SetAllPoints(row)
            host.iconArt:EnableMouse(false)
            host.iconArt:SetFrameStrata(host.strata)
            host.iconArt:SetFrameLevel(host.level + 2)
            host.iconLine = NewTexture(host, 1, host.iconArt)
            -- The new clip takes the host's shown state and anchors.
            host.shownAs, host.placed = nil, nil
            PositionRowDecor(host)
        end
        local texture = host.iconLine
        CUI.PlaceBorderDividerV(texture, fill, false, false, key, step, px, es)
        local topY, bottom = 0, 0
        -- Pinned rows have a separate rail; the scrolling row trims shorten their divider.
        if host.style.bars and host.slot > 0 then
            if host.slot > 1 then
                topY = math.max(0, thick / 32 - gap / 2)
            end
            bottom = math.max(0, thick * 3 / 32 - gap / 2)
        end
        topY = Pix.SnapForES(topY, es)
        if host.slot > 0 and (host.slot ~= 1 or host.pinTop) then
            topY = topY - Pix.perfect / es
        elseif host.slot == -1 then
            topY = topY + Pix.perfect / es
        end
        bottom = Pix.SnapForES(bottom, es)
        if host.joinBottom then
            bottom = bottom - Pix.perfect / es
        end
        if host.slot == 0 then
            bottom = bottom + Pix.perfect / es
        end
        if topY + bottom >= hgt then
            texture:Hide()
        else
            local lead = Pix.SnapForES(thick * 2 / CUI.GetBorderCompanion(key, "sepSize"), es)
            texture:SetPoint("TOPLEFT", fill, "TOPLEFT", -lead, -topY)
            texture:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", -lead, bottom)
        end
        texture:SetVertexColor(r, g, b, a)
    elseif host.iconLine then
        host.iconLine:Hide()
    end
    if host.own and host.style.marker then
        if not host.marker then
            host.marker = NewTexture(host, 2)
            host.marker:SetPoint("TOPLEFT", fill, "TOPLEFT")
            host.marker:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT")
            host.marker:SetWidth(2)
            host.marker:SetColorTexture(1, 1, 1, 0.95)
        end
        host.marker:Show()
    elseif host.marker then
        host.marker:Hide()
    end
end

-- A full re-placement (a new slot, icon or style, a pin flip, a new pixel grid).
local function ReapplyRowDecor(host)
    host.placed = nil
    PositionRowDecor(host)
    PlaceRow(host)
end

local function SyncRowDecor(host, enabled)
    if not enabled then
        HideRowDecor(host)
        return
    end
    local pinTop = host.window.stickyAtTop == true
    if host.active and host.pinTop ~= pinTop then
        host.pinTop = pinTop
        ReapplyRowDecor(host)
    elseif PositionRowDecor(host) then
        PlaceRow(host)
    end
end

function mod.DMSyncRowDecor(wid)
    local c = mod.EDM.DB()
    local enabled = c.barSeparators or c.iconSeparator or c.showPlayerMarker
    for _, bar in ipairs(wid.rowPool) do
        -- A parked host has nothing to follow.
        local host = bar._decor
        if host and (host.active or not enabled) then
            SyncRowDecor(host, enabled)
        end
    end
    if wid.stickyPlayer._decor then
        SyncRowDecor(wid.stickyPlayer._decor, enabled)
    end
    wid._decorSync = enabled or nil
end

function mod.DMApplyRowDecor(bar, window, source, slot)
    local c, host = mod.EDM.DB(), bar._decor
    if not (c.barSeparators or c.iconSeparator or c.showPlayerMarker) then
        if host then
            HideRowDecor(host)
        end
        return
    end
    local style = Style(c)
    local own = style.marker and mod._IsOwnRow(source) or false
    if not style.bars and not style.icons and not own then
        if host then
            HideRowDecor(host)
        end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, window.frame)
        host:SetClipsChildren(true)
        host:EnableMouse(false)
        host.art = CreateFrame("Frame", nil, host)
        host.art:EnableMouse(false)
        host.fill = CreateFrame("Frame", nil, host.art)
        host.fill:EnableMouse(false)
        host.bar, host.window, bar._decor = bar, window, host
    end
    -- Shared levels keep every icon divider above every bar divider, including pinned rows.
    local rowLevel = window.stickyPlayer and window.stickyPlayer.row:GetFrameLevel()
        or window.frame:GetFrameLevel() + 8
    local level = math.max(window.windowBorderTarget:GetFrameLevel() + 4, rowLevel + 7)
    local scale, iconShown = host:GetEffectiveScale(), bar.classIcon:IsShown()
    local strata = window.frame:GetFrameStrata()
    local pinTop = window.stickyAtTop == true
    if
        host:IsShown()
        and host.gen == generation
        and host.style == style
        and host.slot == slot
        and host.own == own
        and host.iconShown == iconShown
        and host.level == level
        and host.scale == scale
        and host.strata == strata
        and host.pinTop == pinTop
    then
        if PositionRowDecor(host) then
            PlaceRow(host)
        end
        return
    end
    host.gen, host.style, host.slot, host.own = generation, style, slot, own
    host.iconShown, host.level, host.scale, host.strata = iconShown, level, scale, strata
    host.pinTop = pinTop
    host.active, window._decorSync = true, true
    host:SetFrameStrata(strata)
    host:SetFrameLevel(level)
    host.art:SetFrameStrata(strata)
    host.art:SetFrameLevel(level + 1)
    if host.iconArt then
        host.iconHost:SetFrameStrata(strata)
        host.iconHost:SetFrameLevel(level + 1)
        host.iconArt:SetFrameStrata(strata)
        host.iconArt:SetFrameLevel(level + 2)
    end
    ReapplyRowDecor(host)
    CUI.RegisterPxReapply(host, (style.icons or (style.bars and c.borderSizePx)) and ReapplyRowDecor or nil)
end

local function PlaceHeader(host)
    local wid, c = host.window, mod.EDM.DB()
    local es = host:GetEffectiveScale()
    local key, step = c.windowBorderTexture, c.windowBorderSize
    local px = CUI.BorderPx(c.windowBorderSizePx, step, key)
    local thick = CUI.BorderCompanionThickness(key, step, px, es)
    local lead = Pix.SnapForES(thick * 2 / CUI.GetBorderCompanion(key, "sepSize"), es)
    local texture, color = host.line, c.windowBorderColor or {}
    texture:SetTexture(CUI.GetBorderCompanion(key, "sepH"))
    texture:SetTexCoord(0, 1, 1, 0)
    texture:SetVertexColor(color.r or 0, color.g or 0, color.b or 0, color.a or 1)
    texture:ClearAllPoints()
    texture:SetPoint("BOTTOMLEFT", wid.header, "BOTTOMLEFT", 0, -lead)
    texture:SetPoint("BOTTOMRIGHT", wid.header, "BOTTOMRIGHT", 0, -lead)
    texture:SetHeight(thick)
end

function mod.DMApplyHeaderSeparator(wid)
    local c, host = mod.EDM.DB(), wid._headerSeparator
    local enabled = c.hdrBottomSeparator
        and not mod.DMBlizz()
        and c.windowBorderIncludeHeader ~= false
        and (c.windowBorderSize or 0) > 0
        and CUI.GetBorderCompanion(c.windowBorderTexture, "sepH") ~= nil
    if not enabled then
        if host then
            host:Hide()
            CUI.RegisterPxReapply(host, nil)
            if not mod.DMBlizz() then
                wid.header._bottomBorder:SetShown((c.hdrBottomBorderSize or 0) > 0)
            end
        end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, wid.frame)
        host:SetAllPoints(wid.frame)
        host:SetClipsChildren(true)
        host:EnableMouse(false)
        host.art = CreateFrame("Frame", nil, host)
        host.art:SetAllPoints(wid.header)
        host.art:EnableMouse(false)
        host.line = NewTexture(host)
        host.window, wid._headerSeparator = wid, host
    end
    host:SetFrameStrata(wid.frame:GetFrameStrata())
    host:SetFrameLevel(wid.windowBorderTarget:GetFrameLevel() + 2)
    host.art:SetFrameLevel(host:GetFrameLevel() + 1)
    wid.header._bottomBorder:Hide()
    host:Show()
    PlaceHeader(host)
    CUI.RegisterPxReapply(host, c.windowBorderSizePx and PlaceHeader or nil)
end

Inner.broken = false
