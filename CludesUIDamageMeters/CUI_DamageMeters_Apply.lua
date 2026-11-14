if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_DamageMeters_Apply.lua
--
--  The ns functions that push a changed setting to every window.
--  Reads the earlier Damage Meters files through ns and ns._dmInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._dmInternals
-- CludesUIDamageMeters.lua or an earlier CUI_DamageMeters_*.lua file
-- failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local CUI = CludesUI

local DB, GetHeaderH, ICON_ALPHA = Inner.DB, Inner.GetHeaderH, Inner.ICON_ALPHA
local _windows = Inner._windows
local ApplyHeaderButtonsHoverVisibility = Inner.ApplyHeaderButtonsHoverVisibility
local LayoutHeaderButtons, GetAccentRGB = Inner.LayoutHeaderButtons, Inner.GetAccentRGB
local PhysicalPixels, SetDMFont = Inner.PhysicalPixels, Inner.SetDMFont

-- ns exports (loop over all windows)
mod.RefreshMeter = function()
    mod.DMInvalidateAppearance()
    local conf = DB()
    for _, wid in ipairs(_windows) do
        if conf.barSeparators or conf.iconSeparator or wid._decorSync then
            mod.DMSetWindowBorderLayer(wid, conf)
        end
        wid.Refresh()
    end
end

-- Re-lay out every row after a UI scale change. The row stride is derived from
-- the frame's effective scale, so a new scale invalidates the cached row
-- anchors; busting _barCacheKey makes the next refresh re-anchor them. Rows are
-- otherwise only re-anchored on a settings change or from the in-combat ticker,
-- so out of combat the old grid would survive until the next fight. Deliberately
-- not _CUDM_Apply (a full re-apply of every window): the core scale slider calls
-- this on every drag step.
mod.Rescale = function()
    mod.DMInvalidateAppearance()
    for _, wid in ipairs(_windows) do
        wid._barCacheKey = nil
        wid.Refresh()
        if wid.sourceOpen and wid.RefreshBreakdown then
            wid.RefreshBreakdown()
        end
    end
    if mod.ApplySpellHistory then
        mod.ApplySpellHistory()
    end
end
-- Called by the core right after PP.SetUIScale, alongside the other modules' re-apply hooks
_G._CUDM_Rescale = mod.Rescale

-- Bust per-class color caches and repaint when global custom class colors change, so bars/text
-- recolor live without a /reload (color is cached keyed only on classFile, which the palette edit doesn't change).
mod.RefreshColors = function()
    for _, wid in ipairs(_windows) do
        wid._stickyClassCache = false
        wid._stickySpecCache = nil
        -- The key bust re-seeds every populated row's colour memo (the full-rebuild pass).
        wid._barCacheKey = nil
        wid.Refresh()
    end
end
-- Exposed on the shared table so the parent addon's ApplyColorsToOUF can repaint damage meters when global custom class colors change
CludesUI._DM_RefreshColors = mod.RefreshColors

-- A Name Format change (the Left Text cog; on WoW Forever also Forever
-- Essentials). The row and pinned-row name memos are keyed on the raw name, so
-- they are dropped before the repaint; the breakdown rows and hover headers are
-- rebuilt on every refresh and show. A hidden window catches up when it shows.
mod.RefreshNames = function()
    for _, wid in ipairs(_windows) do
        local pool = wid.rowPool
        if pool then
            for idx = 1, #pool do
                pool[idx]._cachedSrcName = nil
            end
        end
        wid._stickyNameCache = nil
        wid.Refresh()
    end
end

mod.ApplyBorder = function()
    mod.DMInvalidateAppearance()
    for _, wid in ipairs(_windows) do
        if wid.rowPool then
            for _, bar in ipairs(wid.rowPool) do
                if bar.ApplyBorder then
                    bar.ApplyBorder()
                end
            end
        end
        if wid.stickyPlayer and wid.stickyPlayer.ApplyBorder then
            wid.stickyPlayer.ApplyBorder()
        end
        mod.DMRefreshRowDecor(wid)
    end
end

mod.ApplyBarBg = function()
    for _, wid in ipairs(_windows) do
        if wid.rowPool then
            for _, bar in ipairs(wid.rowPool) do
                if bar.ApplyBg then
                    bar.ApplyBg()
                end
            end
        end
        if wid.stickyPlayer and wid.stickyPlayer.ApplyBg then
            wid.stickyPlayer.ApplyBg()
        end
    end
end

mod.ApplyBarTextOffsets = function()
    for _, wid in ipairs(_windows) do
        if wid.rowPool then
            for _, bar in ipairs(wid.rowPool) do
                if bar.ApplyTextOffsets then
                    bar.ApplyTextOffsets()
                end
            end
        end
        if wid.stickyPlayer and wid.stickyPlayer.ApplyTextOffsets then
            wid.stickyPlayer.ApplyTextOffsets()
        end
    end
end

mod.ApplyBackground = function()
    local conf = DB()
    local r, g, b, a = conf.bgR or 0, conf.bgG or 0, conf.bgB or 0, conf.bgAlpha or 0.75
    for _, wid in ipairs(_windows) do
        if wid.frame and wid.frame._bg then
            mod.DMPaintWindowBg(wid.frame._bg, r, g, b, a, true, conf.bgTexture)
        end
        if wid.sourceFrame and wid.sourceFrame._bg then
            mod.DMPaintWindowBg(wid.sourceFrame._bg, r, g, b, a, nil, conf.bgTexture)
        end
    end
    -- Under Classic WoW UI the header tint is shaded from the window colour.
    if mod.DMClassic() then
        mod.ApplyHeader()
    end
end

mod.ApplyWindowBorder = function()
    mod.DMInvalidateAppearance()
    local conf = DB()
    -- Stock-style windows carry their own frame art (the stock panel, the
    -- classic tooltip edge), no CUI border.
    local size = mod.DMBlizz() and 0 or (tonumber(conf.windowBorderSize) or 0)
    local texture = conf.windowBorderTexture or "solid"
    -- Exact size (nil = the legacy step path); a stock style forces size 0, no px.
    local px = size > 0 and CUI.BorderPx(conf.windowBorderSizePx, size, texture) or nil
    local color = conf.windowBorderColor or {}
    local r, g, b, a = color.r or 0, color.g or 0, color.b or 0, color.a or 1
    local includeHeader = conf.windowBorderIncludeHeader ~= false
    local offsetX = texture ~= "solid" and (tonumber(conf.windowBorderOffsetX) or 0) or 0
    local offsetY = texture ~= "solid" and (tonumber(conf.windowBorderOffsetY) or 0) or 0

    for _, wid in ipairs(_windows) do
        local target = wid.windowBorderTarget
        if target and wid.frame and wid.header then
            local relayered = mod.DMSetWindowBorderLayer(wid, conf)
            target:ClearAllPoints()
            if includeHeader then
                target:SetPoint("TOPLEFT", wid.frame, "TOPLEFT", -offsetX, offsetY)
            else
                target:SetPoint("TOPLEFT", wid.header, "BOTTOMLEFT", -offsetX, offsetY)
            end
            target:SetPoint("BOTTOMRIGHT", wid.frame, "BOTTOMRIGHT", offsetX, -offsetY)
            -- Offsets are represented by the target geometry itself, which also makes them work for the solid four-strip border implementation
            CUI.ApplyBorderStyle(target, size, r, g, b, a, texture, nil, nil, nil, nil, nil, nil, nil, px)
            if conf.hdrBottomSeparator or wid._headerSeparator then
                mod.DMApplyHeaderSeparator(wid)
            end
            -- The row decorations read no window border setting but its level.
            if relayered then
                mod.DMRefreshRowDecor(wid)
            end
        end
    end
    -- Border reach counts in size matching (each window's getMatchPad reads
    -- these settings): re-push a window's matches when it moved (deferred).
    if CUI.MatchPadChanged then
        for idx = 1, #_windows do
            CUI.MatchPadChanged("EDM_Win" .. idx)
        end
    end
end

mod.ApplyHeader = function()
    local conf = DB()
    local hc = conf.hdrBgColor
    local hR = hc and hc.r or 0x1B / 255
    local hG = hc and hc.g or 0x1B / 255
    local hB = hc and hc.b or 0x1B / 255
    local hA = conf.hdrBgAlpha or 1
    local tR, tG, tB
    if conf.hdrTextUseAccent ~= false then
        tR, tG, tB = mod.DMTitleRGB()
    else
        local c = conf.hdrTextColor
        tR = c and c.r or 1
        tG = c and c.g or 1
        tB = c and c.b or 1
    end
    local hdrFS = conf.hdrFontSize or 11
    local hdrH = GetHeaderH()
    local iconSz = mod.DMHdrIconSize(conf)
    for _, wid in ipairs(_windows) do
        if wid.header then
            wid.header:SetHeight(hdrH)
            if wid.header._hdrBg then
                mod.DMPaintHeaderBg(wid.header._hdrBg, hR, hG, hB, hA)
            end
            if
                wid.header._bottomBorder
                and not mod.DMClassicSeparator(wid.header._bottomBorder, PhysicalPixels(1))
            then
                local size = conf.hdrBottomBorderSize or 0
                local color = conf.hdrBottomBorderColor or {}
                wid.header._bottomBorder:SetHeight(PhysicalPixels(size))
                wid.header._bottomBorder:SetColorTexture(
                    color.r or 0,
                    color.g or 0,
                    color.b or 0,
                    color.a or 1
                )
                wid.header._bottomBorder:SetShown(size > 0 and not mod.DMBlizz())
            end
        end
        if wid.frame and wid.frame._bg then
            wid.frame._bg:ClearAllPoints()
            wid.frame._bg:SetPoint("TOPLEFT", wid.frame, "TOPLEFT", 0, -hdrH)
            wid.frame._bg:SetPoint("BOTTOMRIGHT", wid.frame, "BOTTOMRIGHT", 0, 0)
        end
        if wid.titleText then
            SetDMFont(wid.titleText, hdrFS)
            wid.titleText:SetTextColor(tR, tG, tB, 1)
            local txOX, txOY = conf.hdrTextOffX or 0, conf.hdrTextOffY or 0
            wid.titleText:ClearAllPoints()
            wid.titleText:SetPoint("LEFT", wid.header, "LEFT", 6 + txOX, txOY + mod.DMHdrLift(conf.hdrHeight))
        end
        if wid.timerText then
            SetDMFont(wid.timerText, hdrFS)
        end
        LayoutHeaderButtons(wid, conf, iconSz)
        -- Close icon is 2px larger than other icons
        if wid._closeIconTex then
            wid._closeIconTex:ClearAllPoints()
            wid._closeIconTex:SetSize(iconSz + 2, iconSz + 2)
            wid._closeIconTex:SetPoint("CENTER", wid.winActionBtn, "CENTER", 0, 0)
        end

        ApplyHeaderButtonsHoverVisibility(wid, conf)
        wid._fitFull = nil
        if wid.FitTitle then
            wid.FitTitle()
        end
    end
    mod.ApplyWindowBorder()
end

mod.ApplyIconColor = function()
    local conf = DB()
    local r, g, b
    if conf.iconColorUseAccent then
        r, g, b = GetAccentRGB()
    else
        local c = conf.iconColor
        r = c and c.r or 1
        g = c and c.g or 1
        b = c and c.b or 1
    end
    for _, wid in ipairs(_windows) do
        for _, icon in ipairs(wid.hdrIcons) do
            -- Stock-style art carries its own colours.
            if not icon._hdrArt then
                icon:SetVertexColor(r, g, b, ICON_ALPHA)
            end
        end
    end
end

mod.ApplyIconBorder = function()
    for _, wid in ipairs(_windows) do
        if wid.rowPool then
            for _, bar in ipairs(wid.rowPool) do
                if bar.ApplyIconBorder then
                    bar.ApplyIconBorder()
                end
            end
        end
        if wid.stickyPlayer and wid.stickyPlayer.ApplyIconBorder then
            wid.stickyPlayer.ApplyIconBorder()
        end
    end
end

Inner.broken = false
