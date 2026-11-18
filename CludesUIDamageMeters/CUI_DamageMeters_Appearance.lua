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
    for index = 1, total do
        local value = sources[index][range.key]
        -- Secret sessions use the API's existing rank order instead of reading amounts.
        if (issecretvalue and issecretvalue(value)) or type(value) ~= "number" then
            range.low, range.high = nil, nil
            return
        end
        range.low = range.low and math.min(range.low, value) or value
        range.high = range.high and math.max(range.high, value) or value
    end
end

function mod.DMPaintValueGradient(barFrame, window, source, index)
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

local function NewTexture(owner, sub, art)
    local texture = (art or owner.art):CreateTexture(nil, "OVERLAY", nil, sub or 0)
    Pix.DisablePixelSnap(texture)
    return texture
end

-- Parks a host (hidden, out of the UI-scale pass). Returns at once when it is
-- parked already: the marker-only mode parks every other row's host each refresh.
local function HideRowDecor(owner)
    if owner.active == false and owner.shownAs == false then
        return
    end
    owner.active, owner.shownAs, owner.placed = false, false, nil
    owner:Hide()
    if owner.iconHost then
        owner.iconHost:Hide()
    end
    CUI.RegisterPxReapply(owner, nil)
end

-- Follows the row. Re-anchors only when the scroll, the row metrics, the row
-- count, the viewport height or the pin state moved since the last placement
-- (host.placed); slot, icon and style changes clear it (ReapplyRowDecor).
local function PositionRowDecor(owner)
    local wid, barFrame = owner.window, owner.bar
    local visible = (owner.active and barFrame.row:IsShown() and wid.viewport:IsShown()) and true or false
    if owner.shownAs ~= visible then
        owner.shownAs = visible
        owner:SetShown(visible)
        if owner.iconHost then
            owner.iconHost:SetShown(visible)
        end
    end
    if not visible then
        return
    end
    local es = owner:GetEffectiveScale()
    local hgt, _, stride = mod._RowMetrics(owner.style.cfg.barHeight or 18, owner.style.cfg.barSpacing or 2, es)
    local scroll = owner.slot > 0 and wid.viewport:GetVerticalScroll() or 0
    local total, viewH = wid.visibleCount or 0, wid.viewport:GetHeight()
    local atTop = wid.stickyAtTop == true
    local pinBottom = owner.slot > 0 and not atTop and wid.stickyPlayer.row:IsShown()
    if
        owner.placed
        and owner.pEs == es
        and owner.pH == hgt
        and owner.pStride == stride
        and owner.pScroll == scroll
        and owner.pCount == total
        and owner.pViewH == viewH
        and owner.pAtTop == atTop
        and owner.pPinBottom == pinBottom
    then
        return false
    end
    owner.placed, owner.pEs, owner.pH, owner.pStride, owner.pScroll = true, es, hgt, stride, scroll
    owner.pCount, owner.pViewH, owner.pAtTop, owner.pPinBottom = total, viewH, atTop, pinBottom
    local joinBottom = owner.style.icons and pinBottom and owner.slot == math.ceil((scroll + viewH) / stride)
        or false
    local joinChanged = owner.joinBottom ~= joinBottom
    owner.joinBottom = joinBottom
    -- Keep the end separator when the whole list fits without scrolling.
    owner.lineVisible = owner.style.bars
        and (
            owner.slot <= 0
            or (owner.slot < total and owner.slot * stride < scroll + viewH)
            or (owner.slot == total and total * stride <= viewH)
        )
    if owner.line then
        owner.line:SetShown(owner.lineVisible)
    end
    local clip = owner.slot <= 0 and wid.frame or wid.viewport
    owner:ClearAllPoints()
    owner:SetAllPoints(clip)
    owner.art:ClearAllPoints()
    if owner.slot <= 0 then
        owner.art:SetAllPoints(barFrame.row)
    else
        local posY = scroll - (owner.slot - 1) * stride
        owner.art:SetPoint("TOPLEFT", wid.viewport, "TOPLEFT", 0, posY)
        owner.art:SetPoint("TOPRIGHT", wid.viewport, "TOPRIGHT", 0, posY)
        owner.art:SetHeight(hgt)
    end
    owner.fill:ClearAllPoints()
    owner.fill:SetPoint("TOPLEFT", owner.art, "TOPLEFT", owner.iconShown and hgt or 0, 0)
    owner.fill:SetPoint("BOTTOMRIGHT", owner.art, "BOTTOMRIGHT", 0, 0)
    if owner.iconHost then
        owner.iconHost:ClearAllPoints()
        owner.iconHost:SetPoint(
            "TOPLEFT",
            clip,
            "TOPLEFT",
            0,
            owner.slot > 0 and wid.stickyAtTop and Pix.perfect / es or 0
        )
        -- Let the scrolling dividers reach the one-pixel rail above a bottom-pinned row.
        local bottom = pinBottom and -Pix.perfect / es or 0
        owner.iconHost:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, bottom)
    end
    return joinChanged
end

local function PlaceRow(owner)
    local c = owner.style.cfg
    local row, fillTex = owner.art, owner.fill
    local es = owner:GetEffectiveScale()
    local hgt, gap = mod._RowMetrics(c.barHeight or 18, c.barSpacing or 2, es)
    local key, step = c.borderTexture, c.borderSize or 0
    local px = CUI.BorderPx(c.borderSizePx, step, key)
    local thick = CUI.BorderCompanionThickness(key, step, px, es)
    local region, g, b, a = c.borderR or 0, c.borderG or 0, c.borderB or 0, c.borderA or 1
    if owner.style.bars then
        if not owner.line then
            owner.line = NewTexture(owner)
        end
        local texture = owner.line
        local lead = Pix.SnapForES(thick * 2 / CUI.GetBorderCompanion(key, "sepSize"), es)
        texture:SetTexture(CUI.GetBorderCompanion(key, "sepH"))
        texture:SetVertexColor(region, g, b, a)
        texture:ClearAllPoints()
        if owner.slot == -1 then
            texture:SetTexCoord(0, 1, 0, 1)
            texture:SetPoint("TOPLEFT", row, "TOPLEFT", 0, lead)
            texture:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, lead)
        else
            local posY = Pix.SnapForES(-(owner.slot == 0 and 0 or gap / 2) - lead, es)
            texture:SetTexCoord(0, 1, 1, 0)
            texture:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, posY)
            texture:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, posY)
        end
        texture:SetHeight(thick)
        texture:SetShown(owner.lineVisible)
    elseif owner.line then
        owner.line:Hide()
    end
    if owner.style.icons and owner.iconShown then
        if not owner.iconLine then
            -- A sibling clip escapes the scroll frame's flattened render order.
            owner.iconHost = CreateFrame("Frame", nil, owner.window.frame)
            owner.iconHost:SetClipsChildren(true)
            owner.iconHost:EnableMouse(false)
            owner.iconHost:SetFrameStrata(owner.strata)
            owner.iconHost:SetFrameLevel(owner.level + 1)
            owner.iconArt = CreateFrame("Frame", nil, owner.iconHost)
            owner.iconArt:SetAllPoints(row)
            owner.iconArt:EnableMouse(false)
            owner.iconArt:SetFrameStrata(owner.strata)
            owner.iconArt:SetFrameLevel(owner.level + 2)
            owner.iconLine = NewTexture(owner, 1, owner.iconArt)
            -- The new clip takes the host's shown state and anchors.
            owner.shownAs, owner.placed = nil, nil
            PositionRowDecor(owner)
        end
        local texture = owner.iconLine
        CUI.PlaceBorderDividerV(texture, fillTex, false, false, key, step, px, es)
        local topY, bottom = 0, 0
        -- Pinned rows have a separate rail; the scrolling row trims shorten their divider.
        if owner.style.bars and owner.slot > 0 then
            if owner.slot > 1 then
                topY = math.max(0, thick / 32 - gap / 2)
            end
            bottom = math.max(0, thick * 3 / 32 - gap / 2)
        end
        topY = Pix.SnapForES(topY, es)
        if owner.slot > 0 and (owner.slot ~= 1 or owner.pinTop) then
            topY = topY - Pix.perfect / es
        elseif owner.slot == -1 then
            topY = topY + Pix.perfect / es
        end
        bottom = Pix.SnapForES(bottom, es)
        if owner.joinBottom then
            bottom = bottom - Pix.perfect / es
        end
        if owner.slot == 0 then
            bottom = bottom + Pix.perfect / es
        end
        if topY + bottom >= hgt then
            texture:Hide()
        else
            local lead = Pix.SnapForES(thick * 2 / CUI.GetBorderCompanion(key, "sepSize"), es)
            texture:SetPoint("TOPLEFT", fillTex, "TOPLEFT", -lead, -topY)
            texture:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMLEFT", -lead, bottom)
        end
        texture:SetVertexColor(region, g, b, a)
    elseif owner.iconLine then
        owner.iconLine:Hide()
    end
    if owner.own and owner.style.marker then
        if not owner.marker then
            owner.marker = NewTexture(owner, 2)
            owner.marker:SetPoint("TOPLEFT", fillTex, "TOPLEFT")
            owner.marker:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMLEFT")
            owner.marker:SetWidth(2)
            owner.marker:SetColorTexture(1, 1, 1, 0.95)
        end
        owner.marker:Show()
    elseif owner.marker then
        owner.marker:Hide()
    end
end

-- A full re-placement (a new slot, icon or style, a pin flip, a new pixel grid).
local function ReapplyRowDecor(owner)
    owner.placed = nil
    PositionRowDecor(owner)
    PlaceRow(owner)
end

local function SyncRowDecor(owner, enabled)
    if not enabled then
        HideRowDecor(owner)
        return
    end
    local pinTop = owner.window.stickyAtTop == true
    if owner.active and owner.pinTop ~= pinTop then
        owner.pinTop = pinTop
        ReapplyRowDecor(owner)
    elseif PositionRowDecor(owner) then
        PlaceRow(owner)
    end
end

function mod.DMSyncRowDecor(wid)
    local c = mod.EDM.DB()
    local enabled = c.barSeparators or c.iconSeparator or c.showPlayerMarker
    for _, barFrame in ipairs(wid.rowPool) do
        -- A parked host has nothing to follow.
        local owner = barFrame._decor
        if owner and (owner.active or not enabled) then
            SyncRowDecor(owner, enabled)
        end
    end
    if wid.stickyPlayer._decor then
        SyncRowDecor(wid.stickyPlayer._decor, enabled)
    end
    wid._decorSync = enabled or nil
end

function mod.DMApplyRowDecor(barFrame, window, source, slot)
    local c, owner = mod.EDM.DB(), barFrame._decor
    if not (c.barSeparators or c.iconSeparator or c.showPlayerMarker) then
        if owner then
            HideRowDecor(owner)
        end
        return
    end
    local style = Style(c)
    local own = style.marker and mod._IsOwnRow(source) or false
    if not style.bars and not style.icons and not own then
        if owner then
            HideRowDecor(owner)
        end
        return
    end
    if not owner then
        owner = CreateFrame("Frame", nil, window.frame)
        owner:SetClipsChildren(true)
        owner:EnableMouse(false)
        owner.art = CreateFrame("Frame", nil, owner)
        owner.art:EnableMouse(false)
        owner.fill = CreateFrame("Frame", nil, owner.art)
        owner.fill:EnableMouse(false)
        owner.bar, owner.window, barFrame._decor = barFrame, window, owner
    end
    -- Shared levels keep every icon divider above every bar divider, including pinned rows.
    local rowLevel = window.stickyPlayer and window.stickyPlayer.row:GetFrameLevel()
        or window.frame:GetFrameLevel() + 8
    local level = math.max(window.windowBorderTarget:GetFrameLevel() + 4, rowLevel + 7)
    local scale, iconShown = owner:GetEffectiveScale(), barFrame.classIcon:IsShown()
    local strata = window.frame:GetFrameStrata()
    local pinTop = window.stickyAtTop == true
    if
        owner:IsShown()
        and owner.gen == generation
        and owner.style == style
        and owner.slot == slot
        and owner.own == own
        and owner.iconShown == iconShown
        and owner.level == level
        and owner.scale == scale
        and owner.strata == strata
        and owner.pinTop == pinTop
    then
        if PositionRowDecor(owner) then
            PlaceRow(owner)
        end
        return
    end
    owner.gen, owner.style, owner.slot, owner.own = generation, style, slot, own
    owner.iconShown, owner.level, owner.scale, owner.strata = iconShown, level, scale, strata
    owner.pinTop = pinTop
    owner.active, window._decorSync = true, true
    owner:SetFrameStrata(strata)
    owner:SetFrameLevel(level)
    owner.art:SetFrameStrata(strata)
    owner.art:SetFrameLevel(level + 1)
    if owner.iconArt then
        owner.iconHost:SetFrameStrata(strata)
        owner.iconHost:SetFrameLevel(level + 1)
        owner.iconArt:SetFrameStrata(strata)
        owner.iconArt:SetFrameLevel(level + 2)
    end
    ReapplyRowDecor(owner)
    CUI.RegisterPxReapply(owner, (style.icons or (style.bars and c.borderSizePx)) and ReapplyRowDecor or nil)
end

local function PlaceHeader(owner)
    local wid, c = owner.window, mod.EDM.DB()
    local es = owner:GetEffectiveScale()
    local key, step = c.windowBorderTexture, c.windowBorderSize
    local px = CUI.BorderPx(c.windowBorderSizePx, step, key)
    local thick = CUI.BorderCompanionThickness(key, step, px, es)
    local lead = Pix.SnapForES(thick * 2 / CUI.GetBorderCompanion(key, "sepSize"), es)
    local texture, color = owner.line, c.windowBorderColor or {}
    texture:SetTexture(CUI.GetBorderCompanion(key, "sepH"))
    texture:SetTexCoord(0, 1, 1, 0)
    texture:SetVertexColor(color.r or 0, color.g or 0, color.b or 0, color.a or 1)
    texture:ClearAllPoints()
    texture:SetPoint("BOTTOMLEFT", wid.header, "BOTTOMLEFT", 0, -lead)
    texture:SetPoint("BOTTOMRIGHT", wid.header, "BOTTOMRIGHT", 0, -lead)
    texture:SetHeight(thick)
end

function mod.DMApplyHeaderSeparator(wid)
    local c, owner = mod.EDM.DB(), wid._headerSeparator
    local enabled = c.hdrBottomSeparator
        and not mod.DMBlizz()
        and c.windowBorderIncludeHeader ~= false
        and (c.windowBorderSize or 0) > 0
        and CUI.GetBorderCompanion(c.windowBorderTexture, "sepH") ~= nil
    if not enabled then
        if owner then
            owner:Hide()
            CUI.RegisterPxReapply(owner, nil)
            if not mod.DMBlizz() then
                wid.header._bottomBorder:SetShown((c.hdrBottomBorderSize or 0) > 0)
            end
        end
        return
    end
    if not owner then
        owner = CreateFrame("Frame", nil, wid.frame)
        owner:SetAllPoints(wid.frame)
        owner:SetClipsChildren(true)
        owner:EnableMouse(false)
        owner.art = CreateFrame("Frame", nil, owner)
        owner.art:SetAllPoints(wid.header)
        owner.art:EnableMouse(false)
        owner.line = NewTexture(owner)
        owner.window, wid._headerSeparator = wid, owner
    end
    owner:SetFrameStrata(wid.frame:GetFrameStrata())
    owner:SetFrameLevel(wid.windowBorderTarget:GetFrameLevel() + 2)
    owner.art:SetFrameLevel(owner:GetFrameLevel() + 1)
    wid.header._bottomBorder:Hide()
    owner:Show()
    PlaceHeader(owner)
    CUI.RegisterPxReapply(owner, c.windowBorderSizePx and PlaceHeader or nil)
end

Inner.broken = false
